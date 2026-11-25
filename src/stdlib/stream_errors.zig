// php 8.6's stream errors (main/streams/stream_errors.c): a stream function
// runs as an operation, and the errors its wrappers and streams raise while
// it runs are reported when it ends, the way the context it ran with asks
// (the stream context options error_mode, error_store and error_handler):
// as warnings (the default), as a StreamException carrying them all, or not
// at all; kept for stream_last_errors(); handed to a callback.
//
// an operation whose context sets none of the three options reports its
// errors as they come, which is what the warnings come out as anyway: only
// an operation run with error options collects its errors until it ends
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const callables = @import("../runtime/callables.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!NativeResult;

pub const code_class = "StreamErrorCode";
pub const mode_class = "StreamErrorMode";
pub const store_class = "StreamErrorStore";
pub const error_class = "StreamError";
pub const exception_class = "StreamException";

pub const E_WARNING: i64 = 2;
pub const E_NOTICE: i64 = 8;

// the StreamErrorCode cases in the stub's order; the tag is php's case id,
// which is what a StreamException's code is
pub const Code = enum(u8) {
    None = 1,
    Generic,
    ReadFailed,
    WriteFailed,
    SeekFailed,
    SeekNotSupported,
    FlushFailed,
    TruncateFailed,
    ConnectFailed,
    BindFailed,
    ListenFailed,
    AcceptFailed,
    NotWritable,
    NotReadable,
    Disabled,
    NotFound,
    PermissionDenied,
    AlreadyExists,
    InvalidPath,
    PathTooLong,
    OpenFailed,
    CreateFailed,
    DupFailed,
    UnlinkFailed,
    RenameFailed,
    MkdirFailed,
    RmdirFailed,
    StatFailed,
    MetaFailed,
    ChmodFailed,
    ChownFailed,
    CopyFailed,
    TouchFailed,
    InvalidMode,
    InvalidMeta,
    ModeNotSupported,
    Readonly,
    RecursionDetected,
    NotImplemented,
    NoOpener,
    PersistentNotSupported,
    WrapperNotFound,
    WrapperDisabled,
    ProtocolUnsupported,
    WrapperRegistrationFailed,
    WrapperUnregistrationFailed,
    WrapperRestorationFailed,
    FilterNotFound,
    FilterFailed,
    CastFailed,
    CastNotSupported,
    MakeSeekableFailed,
    BufferedDataLost,
    NetworkSendFailed,
    NetworkRecvFailed,
    SslNotSupported,
    ResumptionFailed,
    SocketPathTooLong,
    OobNotSupported,
    ProtocolError,
    InvalidUrl,
    InvalidResponse,
    InvalidHeader,
    InvalidParam,
    RedirectLimit,
    AuthFailed,
    TimeOut,
    ArchivingFailed,
    EncodingFailed,
    DecodingFailed,
    InvalidFormat,
    AllocationFailed,
    TemporaryFileFailed,
    LockFailed,
    LockNotSupported,
    UserspaceNotImplemented,
    UserspaceInvalidReturn,
    UserspaceCallFailed,
};

const code_names = blk: {
    const fields = @typeInfo(Code).@"enum".field_names;
    var names: [fields.len][]const u8 = undefined;
    for (fields, 0..) |f, i| names[i] = f;
    break :blk names;
};

const mode_names = [_][]const u8{ "Error", "Exception", "Silent" };
const store_names = [_][]const u8{ "Auto", "None", "NonTerminating", "Terminating", "All" };

const Mode = enum { err, exception, silent };
const Store = enum { none, non_terminating, terminating, all };

// the wrapper names php's wrappers report (wops->label)
pub const plainfile = "plainfile";
pub const user_space = "user-space";
pub const php_wrapper = "PHP";
pub const no_wrapper = ":na";

// --- the state an operation collects into -----------------------------------

// PHP_STREAM_ERROR_MAX_DEPTH
const max_depth = 1000;

pub const Entry = struct {
    message: []u8,
    code: Code,
    wrapper: []const u8,
    severity: i64,
    terminating: bool,

    fn free(self: Entry, a: Allocator) void {
        a.free(self.message);
    }
};

const Op = struct {
    // the context the operation reports with, held while it runs; null for
    // one that reports as it goes
    context: ?*PhpObject,
    collecting: bool,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
};

// FG(stream_error_state): the running operations, innermost last, and the
// errors the last operation that stored any kept
pub const State = struct {
    ops: std.ArrayListUnmanaged(Op) = .empty,
    // while an operation reports, the operations under it are out of reach:
    // errors raised by its handler are reported on their own
    floor: usize = 0,
    // operations the depth limit turned down, each ending without a trace
    refused: u32 = 0,
    stored: std.ArrayListUnmanaged(Entry) = .empty,

    fn freeEntries(list: *std.ArrayListUnmanaged(Entry), a: Allocator) void {
        for (list.items) |e| e.free(a);
        list.clearRetainingCapacity();
    }

    // php_stream_error_state_cleanup, at the end of a request
    pub fn reset(self: *State, vm: *VM) void {
        const a = vm.allocator;
        for (self.ops.items) |*op| {
            freeEntries(&op.entries, a);
            op.entries.deinit(a);
            if (op.context) |c| vm.releaseValue(.{ .resource = c });
        }
        self.ops.clearRetainingCapacity();
        freeEntries(&self.stored, a);
        self.floor = 0;
        self.refused = 0;
    }

    pub fn deinit(self: *State, vm: *VM) void {
        self.reset(vm);
        self.ops.deinit(vm.allocator);
        self.stored.deinit(vm.allocator);
    }
};

fn optionOf(context: ?*PhpObject, name: []const u8) ?Value {
    return @import("http_wrapper.zig").contextOption(context, "stream", name);
}

// whether a context sets any of the error options
pub fn hasErrorOptions(context: ?*PhpObject) bool {
    inline for (.{ "error_mode", "error_store", "error_handler" }) |name| {
        if (optionOf(context, name) != null) return true;
    }
    return false;
}

// whether an options array (stream_context_set_default's) sets any of them
pub fn optionsHaveErrorSettings(options: *PhpArray) bool {
    const stream = options.get(.{ .string = Value.String.borrowed("stream") });
    if (stream != .array) return false;
    inline for (.{ "error_mode", "error_store", "error_handler" }) |name| {
        if (stream.array.contains(.{ .string = Value.String.borrowed(name) })) return true;
    }
    return false;
}

fn caseIndex(v: Value, class: []const u8, names: []const []const u8) ?usize {
    if (v != .object or !std.mem.eql(u8, v.object.class_name, class)) return null;
    const n = v.object.get("name");
    if (n != .string) return null;
    for (names, 0..) |name, i| if (std.mem.eql(u8, name, n.string.bytes())) return i;
    return null;
}

fn typeError(ctx: *NativeContext, msg: []const u8) RuntimeError!void {
    try ctx.vm.setPendingException("TypeError", msg);
}

// php_stream_get_error_mode
fn modeOf(ctx: *NativeContext, context: ?*PhpObject) RuntimeError!Mode {
    const v = optionOf(context, "error_mode") orelse return .err;
    const i = caseIndex(v, mode_class, &mode_names) orelse {
        try typeError(ctx, "stream context option 'error_mode' must be of type StreamErrorMode");
        return .err;
    };
    return @enumFromInt(i);
}

fn autoStore(mode: Mode) Store {
    return switch (mode) {
        .err => .none,
        .exception => .non_terminating,
        .silent => .all,
    };
}

// php_stream_get_error_store_mode
fn storeOf(ctx: *NativeContext, context: ?*PhpObject, mode: Mode) RuntimeError!Store {
    const v = optionOf(context, "error_store") orelse return autoStore(mode);
    const i = caseIndex(v, store_class, &store_names) orelse {
        try typeError(ctx, "stream context option 'error_store' must be of type StreamErrorStore");
        return autoStore(mode);
    };
    return switch (i) {
        0 => autoStore(mode),
        1 => .none,
        2 => .non_terminating,
        3 => .terminating,
        else => .all,
    };
}

// --- operations ----------------------------------------------------------------

// php_stream_error_operation_begin: context is the one the operation reports
// with (the default context when null)
pub fn begin(ctx: *NativeContext, context: ?*PhpObject) RuntimeError!void {
    const vm = ctx.vm;
    const state = &vm.stream_errors;
    if (state.ops.items.len >= max_depth) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Stream error operation depth exceeded ({d}), possible infinite recursion", .{state.ops.items.len});
        defer ctx.allocator.free(msg);
        state.refused += 1;
        return @import("filesystem.zig").docrefBody(ctx, E_WARNING, msg);
    }
    const reporting = context orelse vm.default_stream_context;
    const collects = hasErrorOptions(reporting);
    if (collects) VM.objRetain(reporting.?);
    state.ops.append(vm.allocator, .{ .context = if (collects) reporting else null, .collecting = collects }) catch |err| {
        if (collects) vm.releaseValue(.{ .resource = reporting.? });
        return err;
    };
}

fn currentOp(state: *State) ?*Op {
    if (state.ops.items.len <= state.floor) return null;
    return &state.ops.items[state.ops.items.len - 1];
}

// php_stream_error_operation_end: the operation's errors reported as its
// context asks
pub fn end(ctx: *NativeContext) RuntimeError!void {
    const vm = ctx.vm;
    const state = &vm.stream_errors;
    if (state.refused > 0) {
        state.refused -= 1;
        return;
    }
    if (currentOp(state) == null) return;
    var op = state.ops.pop().?;
    defer op.entries.deinit(vm.allocator);
    defer if (op.context) |c| vm.releaseValue(.{ .resource = c });
    if (!op.collecting or op.entries.items.len == 0) {
        State.freeEntries(&op.entries, vm.allocator);
        return;
    }
    return report(ctx, op.context, &op.entries);
}

// an operation unwound by exit: its errors go unreported
pub fn abort(vm: *VM) void {
    const state = &vm.stream_errors;
    if (state.refused > 0) {
        state.refused -= 1;
        return;
    }
    if (currentOp(state) == null) return;
    var op = state.ops.pop().?;
    State.freeEntries(&op.entries, vm.allocator);
    op.entries.deinit(vm.allocator);
    if (op.context) |c| vm.releaseValue(.{ .resource = c });
}

// php_stream_report_errors and the storing after it; takes the entries
fn report(ctx: *NativeContext, context: ?*PhpObject, entries: *std.ArrayListUnmanaged(Entry)) RuntimeError!void {
    const vm = ctx.vm;
    const state = &vm.stream_errors;
    defer State.freeEntries(entries, vm.allocator);
    const mode = try modeOf(ctx, context);
    const store = try storeOf(ctx, context, mode);
    var terminating = false;
    for (entries.items) |e| terminating = terminating or e.terminating;

    var failure: ?RuntimeError = null;
    {
        const saved_floor = state.floor;
        state.floor = state.ops.items.len;
        defer state.floor = saved_floor;
        switch (mode) {
            .err => for (entries.items) |e| {
                @import("filesystem.zig").docrefBody(ctx, e.severity, e.message) catch |err| {
                    failure = err;
                    break;
                };
            },
            .exception => if (terminating) try throwException(ctx, entries.items),
            .silent => {},
        }
        if (failure == null) {
            if (optionOf(context, "error_handler")) |handler| callHandler(ctx, handler, entries.items) catch |err| {
                failure = err;
            };
        }
    }

    if (store != .none) {
        var kept: usize = 0;
        for (entries.items) |e| {
            if (keeps(store, e)) kept += 1;
        }
        if (kept > 0) {
            State.freeEntries(&state.stored, vm.allocator);
            try state.stored.ensureTotalCapacity(vm.allocator, kept);
            var i: usize = 0;
            while (i < entries.items.len) {
                const e = entries.items[i];
                if (keeps(store, e)) {
                    state.stored.appendAssumeCapacity(e);
                    _ = entries.orderedRemove(i);
                } else i += 1;
            }
        }
    }
    if (failure) |err| return err;
}

fn keeps(store: Store, e: Entry) bool {
    return switch (store) {
        .none => false,
        .all => true,
        .non_terminating => !e.terminating,
        .terminating => e.terminating,
    };
}

// php_stream_call_error_handler: the handler gets the errors as StreamError
// objects; an exception already on its way leaves it uncalled
fn callHandler(ctx: *NativeContext, handler: Value, entries: []const Entry) RuntimeError!void {
    const vm = ctx.vm;
    if (vm.pending_exception != null) return;
    switch (try callables.resolveCallback(vm, handler, .{ .deprecations = false })) {
        .failure => |failure| {
            if (vm.pending_exception != null) return;
            var reason: std.ArrayListUnmanaged(u8) = .empty;
            defer reason.deinit(ctx.allocator);
            try callables.writeReason(failure, &reason, ctx.allocator);
            const msg = try std.fmt.allocPrint(ctx.allocator, "stream error handler must be a valid callback, {s}", .{reason.items});
            defer ctx.allocator.free(msg);
            try vm.setPendingException("TypeError", msg);
            return;
        },
        .callee => {},
    }
    const arr = try errorArray(ctx, entries);
    _ = ctx.invokeCallable(handler, &.{.{ .array = arr }}) catch |err| {
        if (err == error.OutOfMemory or vm.pending_exception == null) return err;
    };
}

// php_stream_throw_exception_with_errors: the first error's message and
// code, and every error; one already thrown becomes its previous
fn throwException(ctx: *NativeContext, entries: []const Entry) RuntimeError!void {
    const vm = ctx.vm;
    const first = entries[0];
    const previous = vm.takePending();
    defer if (previous) |p| vm.stackRelease(p);
    try vm.setPendingException(exception_class, first.message);
    const exc = vm.pending_exception.?.object;
    try exc.set(ctx.allocator, "code", .{ .int = @intFromEnum(first.code) });
    const arr = try errorArray(ctx, entries);
    try exc.set(ctx.allocator, "errors", .{ .array = arr });
    if (previous) |p| try exc.set(ctx.allocator, "previous", p);
}

fn errorObject(ctx: *NativeContext, e: Entry) RuntimeError!*PhpObject {
    const obj = try ctx.createObject(error_class);
    const def = ctx.vm.classes.getPtr(code_class).?;
    const case = def.constants.get(@tagName(e.code)).?;
    try obj.set(ctx.allocator, "code", case);
    try obj.setCopiedString(ctx.allocator, "message", e.message);
    try obj.setCopiedString(ctx.allocator, "wrapperName", e.wrapper);
    try obj.set(ctx.allocator, "severity", .{ .int = e.severity });
    try obj.set(ctx.allocator, "terminating", .{ .bool = e.terminating });
    return obj;
}

fn errorArray(ctx: *NativeContext, entries: []const Entry) RuntimeError!*PhpArray {
    const arr = try ctx.createArray();
    for (entries) |e| try arr.append(ctx.allocator, .{ .object = try errorObject(ctx, e) });
    return arr;
}

// --- raising errors --------------------------------------------------------------

pub const Site = struct {
    code: Code,
    wrapper: []const u8 = no_wrapper,
    terminating: bool = true,
    severity: i64 = E_WARNING,
    // the context an error raised outside any operation reports with
    context: ?*PhpObject = null,
};

// php_stream_wrapper_error and friends: the error goes to the running
// operation, which reports it now or when it ends; outside any operation it
// is an operation of its own
pub fn raise(ctx: *NativeContext, site: Site, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    const body = try std.fmt.allocPrint(ctx.vm.allocator, fmt, args);
    return raiseOwned(ctx, site, body);
}

pub fn raiseBody(ctx: *NativeContext, site: Site, body: []const u8) RuntimeError!void {
    return raiseOwned(ctx, site, try ctx.vm.allocator.dupe(u8, body));
}

fn raiseOwned(ctx: *NativeContext, site: Site, body: []u8) RuntimeError!void {
    const vm = ctx.vm;
    const state = &vm.stream_errors;
    if (currentOp(state)) |op| {
        if (op.collecting) {
            return add(vm, op, site, body);
        }
        defer vm.allocator.free(body);
        return @import("filesystem.zig").docrefBody(ctx, site.severity, body);
    }
    const reporting = site.context orelse vm.default_stream_context;
    if (!hasErrorOptions(reporting)) {
        defer vm.allocator.free(body);
        return @import("filesystem.zig").docrefBody(ctx, site.severity, body);
    }
    begin(ctx, reporting) catch |err| {
        vm.allocator.free(body);
        return err;
    };
    if (currentOp(state)) |op| try add(vm, op, site, body) else vm.allocator.free(body);
    return end(ctx);
}

fn add(vm: *VM, op: *Op, site: Site, body: []u8) RuntimeError!void {
    op.entries.append(vm.allocator, .{ .message = body, .code = site.code, .wrapper = site.wrapper, .severity = site.severity, .terminating = site.terminating }) catch |err| {
        vm.allocator.free(body);
        return err;
    };
}

// whether errors raised now are held for the end of an operation, so a site
// that would otherwise print them in a different order can hand them over
pub fn isCollecting(vm: *VM) bool {
    const op = currentOp(&vm.stream_errors) orelse return false;
    return op.collecting;
}

pub fn warn(ctx: *NativeContext, code: Code, wrapper: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    return raise(ctx, .{ .code = code, .wrapper = wrapper }, fmt, args);
}

// php_stream_wrapper_warn_nt: a warning that doesn't end the operation
pub fn warnNt(ctx: *NativeContext, code: Code, wrapper: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    return raise(ctx, .{ .code = code, .wrapper = wrapper, .terminating = false }, fmt, args);
}

pub fn notice(ctx: *NativeContext, code: Code, wrapper: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError!void {
    return raise(ctx, .{ .code = code, .wrapper = wrapper, .terminating = false, .severity = E_NOTICE }, fmt, args);
}

// --- the stream functions that run as operations ---------------------------------

const Spec = union(enum) {
    // the context argument at this index
    context: usize,
    // the context of the stream argument at this index
    stream: usize,
    // the default context
    none,
};

// the functions ext/standard/file.c and streamsfuncs.c wrap in an
// operation, and the context each reports with. opendir, scandir and dir
// raise theirs outside one in php, each error an operation of its own with
// the function's context; they run as one here
const op_specs = .{
    .{ "fopen", Spec{ .context = 3 } },
    .{ "file_get_contents", Spec{ .context = 2 } },
    .{ "file_put_contents", Spec{ .context = 3 } },
    .{ "file", Spec{ .context = 2 } },
    .{ "readfile", Spec{ .context = 2 } },
    .{ "get_meta_tags", Spec.none },
    .{ "mkdir", Spec{ .context = 3 } },
    .{ "rmdir", Spec{ .context = 1 } },
    .{ "rename", Spec{ .context = 2 } },
    .{ "unlink", Spec{ .context = 1 } },
    .{ "copy", Spec{ .context = 2 } },
    .{ "opendir", Spec{ .context = 1 } },
    .{ "scandir", Spec{ .context = 2 } },
    .{ "dir", Spec{ .context = 1 } },
    .{ "tmpfile", Spec.none },
    .{ "popen", Spec.none },
    .{ "fclose", Spec{ .stream = 0 } },
    .{ "pclose", Spec{ .stream = 0 } },
    .{ "flock", Spec{ .stream = 0 } },
    .{ "feof", Spec{ .stream = 0 } },
    .{ "fgets", Spec{ .stream = 0 } },
    .{ "fgetc", Spec{ .stream = 0 } },
    .{ "fscanf", Spec{ .stream = 0 } },
    .{ "fwrite", Spec{ .stream = 0 } },
    .{ "fputs", Spec{ .stream = 0 } },
    .{ "fflush", Spec{ .stream = 0 } },
    .{ "rewind", Spec{ .stream = 0 } },
    .{ "ftell", Spec{ .stream = 0 } },
    .{ "fseek", Spec{ .stream = 0 } },
    .{ "fpassthru", Spec{ .stream = 0 } },
    .{ "fsync", Spec{ .stream = 0 } },
    .{ "fdatasync", Spec{ .stream = 0 } },
    .{ "ftruncate", Spec{ .stream = 0 } },
    .{ "fstat", Spec{ .stream = 0 } },
    .{ "fread", Spec{ .stream = 0 } },
    .{ "fputcsv", Spec{ .stream = 0 } },
    .{ "fgetcsv", Spec{ .stream = 0 } },
    .{ "gzwrite", Spec{ .stream = 0 } },
    .{ "gzputs", Spec{ .stream = 0 } },
    .{ "gzread", Spec{ .stream = 0 } },
    .{ "gzgets", Spec{ .stream = 0 } },
    .{ "gzgetc", Spec{ .stream = 0 } },
    .{ "gzeof", Spec{ .stream = 0 } },
    .{ "gzclose", Spec{ .stream = 0 } },
    .{ "gzrewind", Spec{ .stream = 0 } },
    .{ "gzseek", Spec{ .stream = 0 } },
    .{ "gztell", Spec{ .stream = 0 } },
    .{ "gzpassthru", Spec{ .stream = 0 } },
    .{ "stream_socket_pair", Spec{ .context = 3 } },
    .{ "stream_socket_client", Spec{ .context = 5 } },
    .{ "stream_socket_server", Spec{ .context = 4 } },
    .{ "stream_socket_accept", Spec{ .stream = 0 } },
    .{ "stream_socket_get_name", Spec{ .stream = 0 } },
    .{ "stream_socket_sendto", Spec{ .stream = 0 } },
    .{ "stream_socket_recvfrom", Spec{ .stream = 0 } },
    .{ "stream_socket_enable_crypto", Spec{ .stream = 0 } },
    .{ "stream_socket_shutdown", Spec{ .stream = 0 } },
    .{ "stream_get_contents", Spec{ .stream = 0 } },
    .{ "stream_copy_to_stream", Spec{ .context = 4 } },
    .{ "stream_get_meta_data", Spec{ .stream = 0 } },
    .{ "socket_get_status", Spec{ .stream = 0 } },
    .{ "stream_select", Spec{ .context = 5 } },
    .{ "stream_get_line", Spec{ .stream = 0 } },
    .{ "stream_set_blocking", Spec{ .stream = 0 } },
    .{ "socket_set_blocking", Spec{ .stream = 0 } },
    .{ "stream_set_timeout", Spec{ .stream = 0 } },
    .{ "socket_set_timeout", Spec{ .stream = 0 } },
    .{ "stream_set_write_buffer", Spec{ .stream = 0 } },
    .{ "set_file_buffer", Spec{ .stream = 0 } },
    .{ "stream_set_chunk_size", Spec{ .stream = 0 } },
    .{ "stream_set_read_buffer", Spec{ .stream = 0 } },
    .{ "stream_is_local", Spec{ .context = 1 } },
    .{ "stream_supports_lock", Spec{ .stream = 0 } },
    .{ "stream_isatty", Spec{ .stream = 0 } },
};

fn specFor(comptime name: []const u8) ?Spec {
    @setEvalBranchQuota(100000);
    inline for (op_specs) |s| {
        if (comptime std.mem.eql(u8, s[0], name)) return s[1];
    }
    return null;
}

fn contextArg(args: []const Value, index: usize) ?*PhpObject {
    if (index >= args.len) return null;
    const v = args[index];
    if (v != .resource or !std.mem.eql(u8, v.resource.class_name, "StreamContext")) return null;
    return v.resource;
}

fn streamContext(args: []const Value, index: usize) ?*PhpObject {
    if (index >= args.len) return null;
    const v = args[index];
    if (v != .resource) return null;
    const c = v.resource.get("__context");
    return if (c == .resource) c.resource else null;
}

// the native for name: run as an operation when php runs it as one
pub fn wrap(comptime name: []const u8, comptime f: anytype) NativeFn {
    const spec = comptime specFor(name) orelse return f;
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const context: ?*PhpObject = switch (spec) {
                .context => |i| contextArg(args, i),
                .stream => |i| streamContext(args, i),
                .none => null,
            };
            try begin(ctx, context);
            const result = f(ctx, args) catch |err| {
                if (ctx.vm.exit_requested or err == error.OutOfMemory) {
                    abort(ctx.vm);
                    return err;
                }
                try end(ctx);
                return err;
            };
            const had_exception = ctx.vm.pending_exception != null;
            end(ctx) catch |err| {
                releaseResult(ctx, result);
                return err;
            };
            if (!had_exception and ctx.vm.pending_exception != null) {
                releaseResult(ctx, result);
                return error.RuntimeError;
            }
            return result;
        }
    }.call;
}

fn releaseResult(ctx: *NativeContext, result: NativeResult) void {
    if (result.value == .string) ctx.vm.releaseValue(result.value);
}

// --- the classes and functions --------------------------------------------------

pub const natives = .{
    .{ "stream_last_errors", native_stream_last_errors },
    .{ "stream_clear_errors", native_stream_clear_errors },
};

pub fn register(vm: *VM, a: Allocator) !void {
    try vm.registerUnitEnum(code_class, &code_names);
    try vm.registerUnitEnum(mode_class, &mode_names);
    try vm.registerUnitEnum(store_class, &store_names);

    var def = ClassDef{ .name = error_class, .is_final = true, .is_readonly = true };
    try def.properties.append(a, .{ .name = "code", .default = .undef, .is_readonly = true, .type_str = code_class });
    try def.properties.append(a, .{ .name = "message", .default = .undef, .is_readonly = true, .type_str = "string" });
    try def.properties.append(a, .{ .name = "wrapperName", .default = .undef, .is_readonly = true, .type_str = "string" });
    try def.properties.append(a, .{ .name = "severity", .default = .undef, .is_readonly = true, .type_str = "int" });
    try def.properties.append(a, .{ .name = "terminating", .default = .undef, .is_readonly = true, .type_str = "bool" });
    def.slot_layout = try vm.buildSlotLayout(&def);
    try vm.classes.put(a, error_class, def);

    var exc = ClassDef{ .name = exception_class, .parent = "Exception" };
    try exc.properties.append(a, .{ .name = "errors", .default = .{ .array = try vm.allocArray() }, .has_default = true, .visibility = .private, .type_str = "array" });
    exc.slot_layout = try vm.buildSlotLayout(&exc);
    try exc.methods.put(a, "getErrors", .{ .name = "getErrors", .arity = 0 });
    try vm.classes.put(a, exception_class, exc);
    try vm.native_fns.put(a, exception_class ++ "::getErrors", getErrors);
}

fn thisObject(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    return if (v == .object) v.object else null;
}

fn getErrors(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisObject(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const errors = this.get("errors");
    if (errors == .array) return NativeResult.borrowed(errors);
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

// php_stream_error_get_last: the errors of the last operation that stored any
fn native_stream_last_errors(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = args;
    return NativeResult.borrowed(.{ .array = try errorArray(ctx, ctx.vm.stream_errors.stored.items) });
}

fn native_stream_clear_errors(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = args;
    State.freeEntries(&ctx.vm.stream_errors.stored, ctx.vm.allocator);
    return NativeResult.scalar(.null);
}
