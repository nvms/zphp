// php's output control (main/output.c) over zphp's one output buffer: the
// stack's levels are offsets into vm.output, a level's buffer running from its
// start to the next level's start (the top one's to the end). a handler's run
// replaces its level's bytes with what the handler returned and passes them
// down, which in the flat buffer is leaving them in place below the level
const std = @import("std");
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const Level = vm_mod.OutputBufferLevel;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Value = @import("../runtime/value.zig").Value;
const callables = @import("../runtime/callables.zig");
const RuntimeError = error{ RuntimeError, OutOfMemory };

// handler flags (php_output.h)
pub const user: u32 = 0x0001;
pub const cleanable: u32 = 0x0010;
pub const flushable: u32 = 0x0020;
pub const removable: u32 = 0x0040;
pub const std_flags: u32 = 0x0070;
pub const started: u32 = 0x1000;
pub const disabled: u32 = 0x2000;
pub const processed: u32 = 0x4000;
pub const produced_output: u32 = 0x8000;

// operations a handler is called with
const op_write: i64 = 0;
const op_start: i64 = 1;
const op_clean: i64 = 2;
const op_flush: i64 = 4;
const op_final: i64 = 8;

const pop_force: u32 = 0x001;
const pop_discard: u32 = 0x010;

pub const default_handler_name = "default output handler";

pub const entries = .{
    .{ "ob_start", native_ob_start },
    .{ "ob_get_clean", native_ob_get_clean },
    .{ "ob_end_clean", native_ob_end_clean },
    .{ "ob_get_contents", native_ob_get_contents },
    .{ "ob_get_level", native_ob_get_level },
    .{ "ob_end_flush", native_ob_end_flush },
    .{ "ob_get_flush", native_ob_get_flush },
    .{ "ob_flush", native_ob_flush },
    .{ "ob_clean", native_ob_clean },
    .{ "ob_get_length", native_ob_get_length },
    .{ "ob_implicit_flush", native_ob_implicit_flush },
    .{ "ob_list_handlers", native_ob_list_handlers },
    .{ "ob_get_status", native_ob_get_status },
};

// PHP_OUTPUT_HANDLER_INITBUF_SIZE
fn initialSize(chunk: usize) usize {
    return if (chunk > 0) std.mem.alignForward(usize, chunk, 4096) else 16384;
}

fn top(vm: *VM) ?*Level {
    if (vm.ob_stack.items.len == 0) return null;
    sync(vm);
    return &vm.ob_stack.items[vm.ob_stack.items.len - 1];
}

// a level never starts past the output: code that sends the output on (the
// error display, a write to stderr) keeps what the levels hold, but a level
// must not point past what is left
fn sync(vm: *VM) void {
    var floor: usize = 0;
    for (vm.ob_stack.items) |*level| {
        level.start = @min(@max(level.start, floor), vm.output.items.len);
        floor = level.start;
    }
}

// the bytes a level holds: up to the next level, or the end for the top one.
// a disabled level stores nothing: what reaches it passes below
fn levelEnd(vm: *VM, index: usize) usize {
    return if (index + 1 < vm.ob_stack.items.len) vm.ob_stack.items[index + 1].start else vm.output.items.len;
}

fn settle(vm: *VM, index: usize) void {
    const level = &vm.ob_stack.items[index];
    if (level.flags & disabled != 0) {
        const end = levelEnd(vm, index);
        level.start = end;
    }
}

fn used(vm: *VM, index: usize) usize {
    settle(vm, index);
    return levelEnd(vm, index) - vm.ob_stack.items[index].start;
}

// the buffer grows as php_output_handler_append grows it
fn noteUsed(level: *Level, n: usize) void {
    if (level.buffer_size > n) return;
    const grow = @max(initialSize(level.chunk_size), initialSize(n - level.buffer_size));
    level.buffer_size += grow;
}

pub fn freeLevel(vm: *VM, level: *Level) void {
    if (level.callback) |cb| vm.releaseValue(cb);
    level.callback = null;
    if (level.name.len > 0 and level.name.ptr != default_handler_name.ptr) vm.allocator.free(level.name);
    level.name = "";
}

// every level dropped, handlers not run (vm teardown)
pub fn releaseAll(vm: *VM) void {
    for (vm.ob_stack.items) |*level| freeLevel(vm, level);
    vm.ob_stack.clearRetainingCapacity();
    vm.ob_running = null;
    vm.ob_chunk_watch = false;
}

fn refreshChunkWatch(vm: *VM) void {
    var watch = false;
    for (vm.ob_stack.items) |level| watch = watch or level.chunk_size > 0;
    vm.ob_chunk_watch = watch;
}

// php_output_lock_error: an output buffering operation from inside a running
// handler ends output (every buffer dropped) and the script
fn lockFatal(vm: *VM, comptime func: []const u8) RuntimeError {
    if (vm.ob_stack.items.len > 0) vm.output.shrinkRetainingCapacity(vm.ob_stack.items[0].start);
    releaseAll(vm);
    vm.ob_deactivated = true;
    return vm.raiseFatal(func ++ "(): Cannot use output buffering in output buffering display handlers");
}

const Status = enum { failure, no_data, success };

const Outcome = struct {
    status: Status,
    // what the handler passes below, owned
    out: ?[]u8 = null,
    // an exception the handler threw, raised once the operation is done
    failed: bool = false,
};

// php_output_handler_op on the level at index, whose bytes run to the end
// of the output (every level above it is empty). the level's bytes are taken
// out of the output whenever the handler runs
fn handlerOp(vm: *VM, ctx: *NativeContext, index: usize, op_in: i64, comptime func: []const u8) RuntimeError!Outcome {
    settle(vm, index);
    var level = &vm.ob_stack.items[index];
    if (level.flags & disabled != 0) return .{ .status = .failure };
    if (op_in != op_write and vm.ob_running != null) return lockFatal(vm, func);
    const n = vm.output.items.len - level.start;
    noteUsed(level, n);
    // a write is stored unless it fills a chunk
    if (op_in == op_write and (level.chunk_size == 0 or n < level.chunk_size or vm.ob_running != null)) return .{ .status = .no_data };

    var op = op_in;
    if (level.flags & started == 0) op |= op_start;
    const id = level.id;
    const start = level.start;
    var outcome: Outcome = .{ .status = .no_data };

    if (level.callback) |cb| {
        const raw = try Value.String.create(vm.allocator, vm.output.items[start..]);
        defer raw.release();
        const before = vm.output.items.len;
        const outer_running = vm.ob_running;
        vm.ob_running = index;
        const result = ctx.invokeCallable(cb, &.{ .{ .string = raw }, .{ .int = op } });
        vm.ob_running = outer_running;
        // a lock error inside the handler took the whole stack down
        if (vm.ob_deactivated or index >= vm.ob_stack.items.len or vm.ob_stack.items[index].id != id) {
            _ = result catch |err| return err;
            return .{ .status = .no_data };
        }
        level = &vm.ob_stack.items[index];
        // what the handler printed was stored in its own buffer, after its input
        var echoed: []u8 = &.{};
        defer vm.allocator.free(echoed);
        if (vm.output.items.len > before) echoed = try vm.allocator.dupe(u8, vm.output.items[before..]);
        vm.output.shrinkRetainingCapacity(start);
        level.start = start;
        if (result) |value| {
            // the result is read before anything else runs php code
            if (value == .bool and !value.bool) {
                outcome.status = .failure;
            } else if (value != .bool) {
                const text = @import("strings.zig").coerceToString(ctx, value) catch |err| blk: {
                    if (err == error.OutOfMemory) return err;
                    outcome.failed = true;
                    break :blk "";
                };
                if (text.len > 0) {
                    outcome.out = try vm.allocator.dupe(u8, text);
                    outcome.status = .success;
                }
            }
            if (echoed.len > 0) {
                // the warning is written while the handler is disabled, so it
                // passes below this level
                level.flags |= disabled;
                const msg = try std.fmt.allocPrint(vm.allocator, func ++ "(): Producing output from user output handler {s} is deprecated", .{level.name});
                defer vm.allocator.free(msg);
                const raised = vm.raiseError(VM.E_DEPRECATED, msg);
                if (index >= vm.ob_stack.items.len or vm.ob_stack.items[index].id != id) {
                    if (outcome.out) |out| vm.allocator.free(out);
                    raised catch |err| return err;
                    return .{ .status = .no_data };
                }
                level = &vm.ob_stack.items[index];
                level.flags &= ~disabled;
                level.start = vm.output.items.len;
                raised catch {
                    outcome.failed = true;
                };
            }
        } else |_| {
            outcome.status = .failure;
            outcome.failed = true;
        }
        if (outcome.status == .failure) {
            // the handler's buffer goes below unchanged
            var passed: std.ArrayListUnmanaged(u8) = .empty;
            try passed.appendSlice(vm.allocator, raw.bytes());
            try passed.appendSlice(vm.allocator, echoed);
            outcome.out = try passed.toOwnedSlice(vm.allocator);
        }
    } else if (level.rewriter != 0) {
        // the url rewriter scans what it has; a flush or the final call
        // hands over what it held back too
        const kind: @import("url_scanner.zig").Kind = @enumFromInt(level.rewriter);
        outcome.out = try @import("url_scanner.zig").handle(vm, kind, vm.output.items[start..], op & (op_flush | op_final) != 0);
        vm.output.shrinkRetainingCapacity(start);
        outcome.status = if (outcome.out.?.len > 0) .success else .no_data;
    } else {
        // the default handler passes its input along; ob_gzhandler, with no
        // request asking for compression, fails and so passes it along too
        outcome.out = try vm.allocator.dupe(u8, vm.output.items[start..]);
        vm.output.shrinkRetainingCapacity(start);
        outcome.status = if (level.gzip) .failure else if (outcome.out.?.len > 0) .success else .no_data;
    }
    level.flags |= started;
    switch (outcome.status) {
        .failure => level.flags |= disabled,
        .no_data, .success => level.flags |= processed,
    }
    return outcome;
}

// output a handler passes below the level at index: written where the level
// starts, which then starts past it
fn writeBelow(vm: *VM, index: usize, bytes: []const u8) !void {
    vm.output.shrinkRetainingCapacity(vm.ob_stack.items[index].start);
    try vm.output.appendSlice(vm.allocator, bytes);
    for (vm.ob_stack.items[index..]) |*level| level.start = vm.output.items.len;
}

fn finish(vm: *VM, outcome: Outcome) RuntimeError!void {
    if (outcome.out) |out| vm.allocator.free(out);
    if (outcome.failed and vm.pending_exception != null) return error.RuntimeError;
}

// php_output_stack_pop. true when the level came off
fn pop(vm: *VM, ctx: *NativeContext, flags: u32, comptime func: []const u8) RuntimeError!bool {
    const level = top(vm) orelse {
        try notice(vm, func ++ "(): Failed to {s} buffer. No buffer to {s}", .{ if (flags & pop_discard != 0) "discard" else "send", if (flags & pop_discard != 0) "discard" else "send" });
        return false;
    };
    if (flags & pop_force == 0 and level.flags & removable == 0) {
        try notice(vm, func ++ "(): Failed to {s} buffer of {s} ({d})", .{ if (flags & pop_discard != 0) "discard" else "send", level.name, vm.ob_stack.items.len - 1 });
        return false;
    }
    const index = vm.ob_stack.items.len - 1;
    var outcome: Outcome = .{ .status = .no_data };
    if (level.flags & disabled == 0) {
        var op = op_final;
        if (flags & pop_discard != 0) op |= op_clean;
        outcome = try handlerOp(vm, ctx, index, op, func);
        if (index >= vm.ob_stack.items.len) return finishPopped(vm, outcome);
    } else settle(vm, index);
    var removed = vm.ob_stack.pop().?;
    // a disabled level's bytes already belong below
    if (outcome.out) |out| if (flags & pop_discard == 0) {
        vm.output.shrinkRetainingCapacity(removed.start);
        try vm.output.appendSlice(vm.allocator, out);
    };
    freeLevel(vm, &removed);
    refreshChunkWatch(vm);
    try finish(vm, outcome);
    if (vm.ob_chunk_watch) try checkChunks(vm);
    return true;
}

fn finishPopped(vm: *VM, outcome: Outcome) RuntimeError!bool {
    try finish(vm, outcome);
    return true;
}

fn notice(vm: *VM, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(vm.allocator, fmt, args);
    defer vm.allocator.free(msg);
    try vm.raiseError(8, msg);
}

fn warning(vm: *VM, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const msg = try std.fmt.allocPrint(vm.allocator, fmt, args);
    defer vm.allocator.free(msg);
    try vm.raiseError(VM.E_WARNING, msg);
}

// a level whose chunk size its buffer reached runs its handler, top down,
// as php_output_op does for a write
pub fn checkChunks(vm: *VM) RuntimeError!void {
    if (vm.ob_running != null) return;
    sync(vm);
    var ctx = vm.makeContext(null);
    var index = vm.ob_stack.items.len;
    while (index > 0) {
        index -= 1;
        const level = &vm.ob_stack.items[index];
        if (level.flags & disabled != 0) {
            settle(vm, index);
            continue;
        }
        if (level.chunk_size == 0 or used(vm, index) < level.chunk_size) return;
        // the bytes above this level are empty when it runs
        if (levelEnd(vm, index) != vm.output.items.len) return;
        const outcome = try handlerOp(vm, &ctx, index, op_write, "ob_start");
        if (index >= vm.ob_stack.items.len) return finish(vm, outcome);
        if (outcome.out) |out| {
            try writeBelow(vm, index, out);
        } else {
            for (vm.ob_stack.items[index..]) |*l| l.start = vm.output.items.len;
        }
        try finish(vm, outcome);
    }
}

// php_request_shutdown's php_output_end_all: every level is flushed through
// its handler, removable or not
pub fn endAll(vm: *VM) RuntimeError!void {
    var ctx = vm.makeContext(null);
    while (vm.ob_stack.items.len > 0) _ = try pop(vm, &ctx, pop_force, "ob_end_flush");
}

fn internalAlias(name: []const u8) bool {
    inline for (.{ "ob_gzhandler", "ob_iconv_handler", "mb_output_handler" }) |alias| {
        if (std.mem.eql(u8, name, alias)) return true;
    }
    return false;
}

fn handlerName(vm: *VM, callback: Value) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(vm.allocator);
    if (callback == .object and std.mem.eql(u8, callback.object.class_name, "Closure")) {
        if (callback.object.closureName()) |name| if (vm.functions.get(name)) |f| {
            try buf.appendSlice(vm.allocator, try vm.funcDisplayName(f));
            return buf.toOwnedSlice(vm.allocator);
        };
        try buf.appendSlice(vm.allocator, "Closure::__invoke");
        return buf.toOwnedSlice(vm.allocator);
    }
    if (callback == .string) {
        // a function by its declared spelling
        const raw = callback.string.bytes();
        try buf.appendSlice(vm.allocator, if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw);
        return buf.toOwnedSlice(vm.allocator);
    }
    try callables.writeName(callback, &buf, vm.allocator);
    return buf.toOwnedSlice(vm.allocator);
}

fn native_ob_start(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const params = @import("html.zig").Params{ .ctx = ctx, .func = "ob_start", .args = args };
    const chunk_arg = try params.int(1, "chunk_size", 0);
    const flags_arg = try params.int(2, "flags", std_flags);
    const handler: Value = if (args.len > 0) args[0] else .null;
    if (vm.ob_deactivated) {
        try notice(vm, "ob_start(): Failed to create buffer", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    var level: Level = .{
        .start = vm.output.items.len,
        .chunk_size = if (chunk_arg > 0) @intCast(chunk_arg) else 0,
        // PHP_OUTPUT_HANDLER_ABILITY_FLAGS
        .flags = @as(u32, @truncate(@as(u64, @bitCast(flags_arg)))) & ~@as(u32, 0xf00f),
        .name = default_handler_name,
    };
    level.buffer_size = initialSize(level.chunk_size);
    if (handler == .string and internalAlias(handler.string.bytes())) {
        // a name an extension registered as an internal handler: zlib's
        // compression, and the charset conversions of iconv and mbstring,
        // which pass the output through unchanged here
        level.name = try vm.allocator.dupe(u8, handler.string.bytes());
        level.gzip = std.mem.eql(u8, level.name, "ob_gzhandler");
    } else if (handler != .null) {
        switch (try callables.resolveCallback(vm, handler, .{})) {
            .failure => |failure| {
                if (vm.pending_exception != null) return error.RuntimeError;
                var reason: std.ArrayListUnmanaged(u8) = .empty;
                defer reason.deinit(vm.allocator);
                try callables.writeReason(failure, &reason, vm.allocator);
                try warning(vm, "ob_start(): {s}", .{reason.items});
                try notice(vm, "ob_start(): Failed to create buffer", .{});
                return NativeResult.scalar(.{ .bool = false });
            },
            .callee => {},
        }
        if (vm.pending_exception != null) return error.RuntimeError;
        level.name = try handlerName(vm, handler);
        level.flags |= user;
        level.callback = handler;
        VM.retainValue(handler);
    }
    if (vm.ob_running != null) {
        freeLevel(vm, &level);
        return lockFatal(vm, "ob_start");
    }
    vm.ob_next_id += 1;
    level.id = vm.ob_next_id;
    vm.ob_stack.append(vm.allocator, level) catch |err| {
        freeLevel(vm, &level);
        return err;
    };
    if (level.chunk_size > 0) vm.ob_chunk_watch = true;
    return NativeResult.scalar(.{ .bool = true });
}

// php_output_start_internal for the url rewriter: a level named
// URL-Rewriter on top of the stack
pub fn startRewriter(vm: *VM, kind: @import("url_scanner.zig").Kind) RuntimeError!void {
    if (vm.ob_deactivated) return;
    var level: Level = .{
        .start = vm.output.items.len,
        .flags = std_flags,
        .name = try vm.allocator.dupe(u8, "URL-Rewriter"),
        .rewriter = @intFromEnum(kind),
    };
    level.buffer_size = initialSize(0);
    vm.ob_next_id += 1;
    level.id = vm.ob_next_id;
    vm.ob_stack.append(vm.allocator, level) catch |err| {
        freeLevel(vm, &level);
        return err;
    };
}

fn native_ob_flush(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const level = top(vm) orelse {
        try notice(vm, "ob_flush(): Failed to flush buffer. No buffer to flush", .{});
        return NativeResult.scalar(.{ .bool = false });
    };
    if (level.flags & flushable == 0) {
        try notice(vm, "ob_flush(): Failed to flush buffer of {s} ({d})", .{ level.name, vm.ob_stack.items.len - 1 });
        return NativeResult.scalar(.{ .bool = false });
    }
    const index = vm.ob_stack.items.len - 1;
    const outcome = try handlerOp(vm, ctx, index, op_flush, "ob_flush");
    if (index < vm.ob_stack.items.len) {
        if (outcome.out) |out| try writeBelow(vm, index, out);
    }
    try finish(vm, outcome);
    if (vm.ob_chunk_watch) try checkChunks(vm);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_ob_clean(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const level = top(vm) orelse {
        try notice(vm, "ob_clean(): Failed to delete buffer. No buffer to delete", .{});
        return NativeResult.scalar(.{ .bool = false });
    };
    if (level.flags & cleanable == 0) {
        try notice(vm, "ob_clean(): Failed to delete buffer of {s} ({d})", .{ level.name, vm.ob_stack.items.len - 1 });
        return NativeResult.scalar(.{ .bool = false });
    }
    const outcome = try handlerOp(vm, ctx, vm.ob_stack.items.len - 1, op_clean, "ob_clean");
    try finish(vm, outcome);
    return NativeResult.scalar(.{ .bool = true });
}

fn native_ob_end_flush(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (top(ctx.vm) == null) {
        try notice(ctx.vm, "ob_end_flush(): Failed to delete and flush buffer. No buffer to delete or flush", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = try pop(ctx.vm, ctx, 0, "ob_end_flush") });
}

fn native_ob_end_clean(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (top(ctx.vm) == null) {
        try notice(ctx.vm, "ob_end_clean(): Failed to delete buffer. No buffer to delete", .{});
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = try pop(ctx.vm, ctx, pop_discard, "ob_end_clean") });
}

fn contents(vm: *VM) !?Value.String {
    _ = top(vm) orelse return null;
    const index = vm.ob_stack.items.len - 1;
    settle(vm, index);
    return try Value.String.create(vm.allocator, vm.output.items[vm.ob_stack.items[index].start..]);
}

fn native_ob_get_flush(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const got = (try contents(vm)) orelse {
        try notice(vm, "ob_get_flush(): Failed to delete and flush buffer. No buffer to delete or flush", .{});
        return NativeResult.scalar(.{ .bool = false });
    };
    errdefer got.release();
    if (!try pop(vm, ctx, 0, "ob_get_flush")) {
        const level = top(vm).?;
        try notice(vm, "ob_get_flush(): Failed to delete buffer of {s} ({d})", .{ level.name, vm.ob_stack.items.len - 1 });
    }
    return NativeResult.takeString(got);
}

fn native_ob_get_clean(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const got = (try contents(vm)) orelse return NativeResult.scalar(.{ .bool = false });
    errdefer got.release();
    if (!try pop(vm, ctx, pop_discard, "ob_get_clean")) {
        const level = top(vm).?;
        try notice(vm, "ob_get_clean(): Failed to delete buffer of {s} ({d})", .{ level.name, vm.ob_stack.items.len - 1 });
    }
    return NativeResult.takeString(got);
}

fn native_ob_get_contents(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const got = (try contents(ctx.vm)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.takeString(got);
}

fn native_ob_get_level(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @intCast(ctx.vm.ob_stack.items.len) });
}

fn native_ob_get_length(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (top(ctx.vm) == null) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(used(ctx.vm, ctx.vm.ob_stack.items.len - 1)) });
}

fn native_ob_implicit_flush(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn native_ob_list_handlers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (ctx.vm.ob_stack.items) |level| try arr.appendCopiedString(ctx.allocator, level.name);
    return NativeResult.borrowed(.{ .array = arr });
}

fn status(ctx: *NativeContext, index: usize) !*@import("../runtime/value.zig").PhpArray {
    const vm = ctx.vm;
    const n = used(vm, index);
    const level = &vm.ob_stack.items[index];
    noteUsed(level, n);
    const arr = try ctx.createArray();
    try arr.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("name") }, level.name);
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("type") }, .{ .int = level.flags & 0xf });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("flags") }, .{ .int = level.flags });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("level") }, .{ .int = @intCast(index) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("chunk_size") }, .{ .int = @intCast(level.chunk_size) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("buffer_size") }, .{ .int = @intCast(level.buffer_size) });
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("buffer_used") }, .{ .int = @intCast(n) });
    return arr;
}

fn native_ob_get_status(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const full = args.len >= 1 and args[0].isTruthy();
    const count = ctx.vm.ob_stack.items.len;
    if (count == 0) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    if (!full) return NativeResult.borrowed(.{ .array = try status(ctx, count - 1) });
    const result = try ctx.createArray();
    for (0..count) |i| try result.append(ctx.allocator, .{ .array = try status(ctx, i) });
    return NativeResult.borrowed(.{ .array = result });
}
