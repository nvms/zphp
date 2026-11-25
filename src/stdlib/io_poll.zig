// php 8.6's Io\Poll (ext/standard/io_poll.c over main/poll): a Context
// watches handles through a backend and wait() hands back the Watchers whose
// events fired. the backends are poll(2) everywhere but windows, epoll on
// linux (what Auto picks there, as php does) and WSAPoll on windows.
//
// ownership follows php's: a Context holds its active watchers, by
// descriptor, in its hidden __watchers array; a Watcher holds its handle and
// data in hidden properties; a StreamPollHandle holds its stream resource.
// the native Ctx and W structs keep the rest, and a watcher's link back to
// its context is a plain pointer the context clears when it goes. a stream
// a watcher is registered with lists the watcher (Stream.poll_watchers), so
// closing it retires the watcher while the descriptor is still open
const std = @import("std");
const builtin = @import("builtin");
const platform = @import("../platform.zig");
const sys = @import("../sys.zig");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpArray = value_mod.PhpArray;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Args = @import("string_ports.zig").Args;
const streams = @import("streams.zig");
const fs = @import("filesystem.zig");
const user_streams = @import("user_streams.zig");
const duration = @import("time_duration.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const is_linux = builtin.os.tag == .linux;
const is_windows = builtin.os.tag == .windows;

const backend_class = "Io\\Poll\\Backend";
const event_class = "Io\\Poll\\Event";
const handle_iface = "Io\\Poll\\Handle";
const watcher_class = "Io\\Poll\\Watcher";
const context_class = "Io\\Poll\\Context";
const stream_handle_class = "StreamPollHandle";

const exc_inactive = "Io\\Poll\\InactiveWatcherException";
const exc_already = "Io\\Poll\\HandleAlreadyWatchedException";
const exc_invalid = "Io\\Poll\\InvalidHandleException";
const exc_unavailable = "Io\\Poll\\BackendUnavailableException";
const exc_init = "Io\\Poll\\FailedContextInitializationException";
const exc_add = "Io\\Poll\\FailedHandleAddException";
const exc_modify = "Io\\Poll\\FailedWatcherModificationException";
const exc_wait = "Io\\Poll\\FailedPollWaitException";

// the Backend enum's cases, in php's order
const Backend = enum(u8) { auto, poll, epoll, kqueue, event_ports, wsapoll };
const backend_names = [_][]const u8{ "Auto", "Poll", "Epoll", "Kqueue", "EventPorts", "WSAPoll" };

// the Event enum's cases; each is the bit 1 << its position
const event_names = [_][]const u8{ "Read", "Write", "Error", "HangUp", "ReadHangUp", "OneShot", "EdgeTriggered" };
const READ: u32 = 0x01;
const WRITE: u32 = 0x02;
const ERROR: u32 = 0x04;
const HUP: u32 = 0x08;
const RDHUP: u32 = 0x10;
const ONESHOT: u32 = 0x20;
const ET: u32 = 0x40;

// php_poll_error, the codes FailedPollOperationException carries
const PollError = enum(i64) { none = 0, system, nomem, invalid, exists, notfound, timeout, interrupted, permission, toobig, again, nosupport };
const error_constants = [_][]const u8{ "ERROR_NONE", "ERROR_SYSTEM", "ERROR_NOMEM", "ERROR_INVALID", "ERROR_EXISTS", "ERROR_NOTFOUND", "ERROR_TIMEOUT", "ERROR_INTERRUPTED", "ERROR_PERMISSION", "ERROR_TOOBIG", "ERROR_AGAIN", "ERROR_NOSUPPORT" };

// ---- registration ----------------------------------------------------------

pub fn register(vm: *VM, a: Allocator) !void {
    try vm.registerUnitEnum(backend_class, &backend_names);
    if (vm.classes.getPtr(backend_class)) |def| {
        try def.methods.put(a, "getAvailableBackends", .{ .name = "getAvailableBackends", .arity = 0, .is_static = true });
        try def.methods.put(a, "isAvailable", .{ .name = "isAvailable", .arity = 0 });
        try def.methods.put(a, "supportsEdgeTriggering", .{ .name = "supportsEdgeTriggering", .arity = 0 });
    }
    try vm.native_fns.put(a, backend_class ++ "::getAvailableBackends", backendGetAvailable);
    try vm.native_fns.put(a, backend_class ++ "::isAvailable", backendIsAvailable);
    try vm.native_fns.put(a, backend_class ++ "::supportsEdgeTriggering", backendSupportsEt);

    try vm.registerUnitEnum(event_class, &event_names);

    try vm.interfaces.put(a, handle_iface, .{ .name = handle_iface });

    var sph = ClassDef{ .name = stream_handle_class, .is_final = true, .uncloneable = true, .no_dynamic_properties = true };
    try sph.interfaces.append(a, handle_iface);
    try sph.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try sph.methods.put(a, "getStream", .{ .name = "getStream", .arity = 0 });
    try sph.methods.put(a, "isValid", .{ .name = "isValid", .arity = 0 });
    try vm.classes.put(a, stream_handle_class, sph);
    try vm.native_fns.put(a, stream_handle_class ++ "::__construct", handleConstruct);
    try vm.native_fns.put(a, stream_handle_class ++ "::getStream", handleGetStream);
    try vm.native_fns.put(a, stream_handle_class ++ "::isValid", handleIsValid);

    var watcher = ClassDef{ .name = watcher_class, .is_final = true, .uncloneable = true, .no_dynamic_properties = true, .native_cleanup = cleanupWatcher };
    try watcher.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0, .visibility = .private, .is_final = true });
    const watcher_methods = .{
        .{ "getHandle", 0, watcherGetHandle },         .{ "getWatchedEvents", 0, watcherGetWatched }, .{ "getTriggeredEvents", 0, watcherGetTriggered },
        .{ "getData", 0, watcherGetData },             .{ "hasTriggered", 1, watcherHasTriggered },   .{ "isActive", 0, watcherIsActive },
        .{ "modify", 2, watcherModify },               .{ "modifyEvents", 1, watcherModifyEvents },   .{ "modifyData", 1, watcherModifyData },
        .{ "remove", 0, watcherRemove },
    };
    inline for (watcher_methods) |m| try watcher.methods.put(a, m[0], .{ .name = m[0], .arity = m[1] });
    try vm.classes.put(a, watcher_class, watcher);
    try vm.native_fns.put(a, watcher_class ++ "::__construct", watcherConstruct);
    inline for (watcher_methods) |m| try vm.native_fns.put(a, watcher_class ++ "::" ++ m[0], m[2]);

    var context = ClassDef{ .name = context_class, .is_final = true, .uncloneable = true, .no_dynamic_properties = true, .native_cleanup = cleanupContext };
    const context_methods = .{ .{ "__construct", 1, contextConstruct }, .{ "add", 3, contextAdd }, .{ "wait", 2, contextWait }, .{ "getBackend", 0, contextGetBackend } };
    inline for (context_methods) |m| try context.methods.put(a, m[0], .{ .name = m[0], .arity = m[1] });
    try vm.classes.put(a, context_class, context);
    inline for (context_methods) |m| try vm.native_fns.put(a, context_class ++ "::" ++ m[0], m[2]);

    // the exceptions
    try vm.classes.put(a, "Io\\IoException", .{ .name = "Io\\IoException", .parent = "Exception" });
    try vm.classes.put(a, "Io\\Poll\\PollException", .{ .name = "Io\\Poll\\PollException", .parent = "Io\\IoException" });
    var failed = ClassDef{ .name = "Io\\Poll\\FailedPollOperationException", .parent = "Io\\Poll\\PollException", .is_abstract = true };
    for (error_constants, 0..) |name, code| {
        try failed.constants.put(a, name, .{ .int = @intCast(code) });
        try failed.constant_order.append(a, name);
        try failed.constant_types.put(a, name, "int");
    }
    try vm.classes.put(a, failed.name, failed);
    inline for (.{ exc_init, exc_add, exc_modify, exc_wait }) |name| {
        try vm.classes.put(a, name, .{ .name = name, .parent = "Io\\Poll\\FailedPollOperationException" });
    }
    inline for (.{ exc_unavailable, exc_inactive, exc_already, exc_invalid }) |name| {
        try vm.classes.put(a, name, .{ .name = name, .parent = "Io\\Poll\\PollException" });
    }
}

// ---- backends and their availability -----------------------------------------

fn epollAvailable() bool {
    const fd = ep.create();
    if (fd < 0) return false;
    ep.close(fd);
    return true;
}

fn isAvailable(b: Backend) bool {
    return switch (b) {
        .auto => true,
        .poll => !is_windows,
        .epoll => epollAvailable(),
        .wsapoll => is_windows,
        .kqueue, .event_ports => false,
    };
}

// php_poll_register_backends: the best one first, what Auto takes
fn bestBackend() Backend {
    if (is_windows) return .wsapoll;
    if (epollAvailable()) return .epoll;
    return .poll;
}

fn supportsEt(b: Backend) bool {
    const resolved = if (b == .auto) bestBackend() else b;
    if (!isAvailable(resolved)) return false;
    return resolved == .epoll;
}

fn enumCase(vm: *VM, class: []const u8, name: []const u8) ?*PhpObject {
    const def = vm.classes.getPtr(class) orelse return null;
    const v = def.constants.get(name) orelse return null;
    return if (v == .object) v.object else null;
}

fn caseIndex(obj: *PhpObject, names: []const []const u8) ?usize {
    const n = obj.get("name");
    if (n != .string) return null;
    for (names, 0..) |name, i| if (std.mem.eql(u8, name, n.string.bytes())) return i;
    return null;
}

fn thisObject(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    return if (v == .object) v.object else null;
}

fn thisBackend(ctx: *NativeContext) Backend {
    const this = thisObject(ctx) orelse return .auto;
    return @enumFromInt(caseIndex(this, &backend_names) orelse 0);
}

fn backendGetAvailable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for ([_]Backend{ .poll, .epoll, .kqueue, .event_ports, .wsapoll }) |b| {
        if (!isAvailable(b)) continue;
        const case = enumCase(ctx.vm, backend_class, backend_names[@intFromEnum(b)]) orelse continue;
        try arr.append(ctx.allocator, .{ .object = case });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn backendIsAvailable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = isAvailable(thisBackend(ctx)) });
}

fn backendSupportsEt(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = supportsEt(thisBackend(ctx)) });
}

// ---- native state --------------------------------------------------------------

// one descriptor the poll(2)/WSAPoll backend watches (php_poll_fd_entry)
const Entry = struct { fd: i64, events: u32, token: u64 };

const Ctx = struct {
    allocator: Allocator,
    backend: Backend,
    // epoll
    epfd: i32 = -1,
    epoll_count: i64 = 0,
    // poll and WSAPoll, kept in descriptor order as php's packed table is
    table: std.ArrayListUnmanaged(Entry) = .empty,
    // some watcher can report data its stream has buffered
    buffered_readers: bool = false,
    next_generation: u32 = 0,
    last_error: PollError = .none,

    fn find(self: *Ctx, fd: i64) ?usize {
        for (self.table.items, 0..) |e, i| if (e.fd == fd) return i;
        return null;
    }
};

const W = struct {
    allocator: Allocator,
    obj: *PhpObject,
    watched: u32 = 0,
    triggered: u32 = 0,
    active: bool = false,
    // deactivated because its stream was closed
    closed: bool = false,
    // a fired one-shot, until modifyEvents()
    disarmed: bool = false,
    // reported from its buffer by the running wait()
    reported: bool = false,
    context: ?*Ctx = null,
    // the Context object, for retiring from its __watchers
    context_obj: ?*PhpObject = null,
    fd: i64 = -1,
    token: u64 = 0,
    // the stream resource whose poll_watchers lists this watcher
    stream: ?*PhpObject = null,
};

fn ctxOf(obj: *PhpObject) ?*Ctx {
    return obj.native.get(Ctx, .poll_context);
}

fn watcherOf(obj: *PhpObject) ?*W {
    return obj.native.get(W, .poll_watcher);
}

fn watcherOfValue(v: Value) ?*W {
    return if (v == .object) watcherOf(v.object) else null;
}

fn watchersOf(context_obj: *PhpObject) ?*PhpArray {
    const v = context_obj.get("__watchers");
    return if (v == .array) v.array else null;
}

// ---- errors ----------------------------------------------------------------------

fn errnoError(e: std.posix.E) PollError {
    return switch (e) {
        .SUCCESS => .none,
        .NOMEM => .nomem,
        .INVAL, .BADF => .invalid,
        .EXIST => .exists,
        .NOENT => .notfound,
        .TIME, .TIMEDOUT => .timeout,
        .INTR => .interrupted,
        .ACCES, .PERM => .permission,
        .MFILE, .NFILE => .toobig,
        .AGAIN => .again,
        .NOSYS, .OPNOTSUPP => .nosupport,
        else => .system,
    };
}

fn throwCode(ctx: *NativeContext, class: []const u8, msg: []const u8, code: i64) RuntimeError {
    try ctx.vm.setPendingException(class, msg);
    if (code != 0) if (ctx.vm.pending_exception) |exc| if (exc == .object) try exc.object.set(ctx.allocator, "code", .{ .int = code });
    return error.RuntimeError;
}

fn throwPlain(ctx: *NativeContext, class: []const u8, msg: []const u8) RuntimeError {
    return throwCode(ctx, class, msg, 0);
}

// ---- the backends --------------------------------------------------------------------

fn initBackend(c: *Ctx) bool {
    if (c.backend != .epoll) return true;
    const fd = ep.create();
    if (fd < 0) {
        c.last_error = .system;
        return false;
    }
    c.epfd = fd;
    return true;
}

// epoll(7), on linux only
const ep = if (is_linux) struct {
    const L = std.os.linux;
    const ADD = L.EPOLL.CTL_ADD;
    const MOD = L.EPOLL.CTL_MOD;
    const DEL = L.EPOLL.CTL_DEL;

    fn create() i32 {
        return std.c.epoll_create1(L.EPOLL.CLOEXEC);
    }

    fn close(fd: i32) void {
        _ = std.c.close(fd);
    }

    fn toNative(events: u32) u32 {
        var native: u32 = 0;
        if (events & READ != 0) native |= L.EPOLL.IN;
        if (events & WRITE != 0) native |= L.EPOLL.OUT;
        if (events & ERROR != 0) native |= L.EPOLL.ERR;
        if (events & HUP != 0) native |= L.EPOLL.HUP;
        if (events & RDHUP != 0) native |= L.EPOLL.RDHUP;
        if (events & ONESHOT != 0) native |= L.EPOLL.ONESHOT;
        if (events & ET != 0) native |= L.EPOLL.ET;
        return native;
    }

    fn fromNative(native: u32) u32 {
        var events: u32 = 0;
        if (native & L.EPOLL.IN != 0) events |= READ;
        if (native & L.EPOLL.OUT != 0) events |= WRITE;
        if (native & L.EPOLL.ERR != 0) events |= ERROR;
        if (native & L.EPOLL.HUP != 0) events |= HUP;
        if (native & L.EPOLL.RDHUP != 0) events |= RDHUP;
        return events;
    }

    // .none on success
    fn ctl(epfd: i32, op: u32, fd: i64, events: u32, token: u64) PollError {
        var ev: L.epoll_event = .{ .events = toNative(events), .data = .{ .u64 = token } };
        const rc = std.c.epoll_ctl(epfd, op, @intCast(fd), if (op == DEL) null else &ev);
        if (rc != -1) return .none;
        const e = std.c.errno(rc);
        // EPERM: the file does not implement polling (regular files, /dev/null)
        if (op == ADD and e == .PERM) return .nosupport;
        return errnoError(e);
    }

    fn wait(allocator: Allocator, epfd: i32, out: []Fired, timeout_ms: i32, err: *PollError) ?usize {
        const events = allocator.alloc(L.epoll_event, out.len) catch {
            err.* = .nomem;
            return null;
        };
        defer allocator.free(events);
        const rc = std.c.epoll_wait(epfd, events.ptr, @intCast(out.len), timeout_ms);
        if (rc < 0) {
            err.* = errnoError(std.c.errno(rc));
            return null;
        }
        const n: usize = @intCast(rc);
        for (events[0..n], 0..) |ev, i| out[i] = .{ .fd = @as(u32, @truncate(ev.data.u64)), .token = ev.data.u64, .revents = fromNative(ev.events) };
        return n;
    }
} else struct {
    const ADD = 1;
    const MOD = 3;
    const DEL = 2;

    fn create() i32 {
        return -1;
    }

    fn close(_: i32) void {}

    fn ctl(_: i32, _: u32, _: i64, _: u32, _: u64) PollError {
        return .nosupport;
    }

    fn wait(_: Allocator, _: i32, _: []Fired, _: i32, err: *PollError) ?usize {
        err.* = .nosupport;
        return null;
    }
};

fn epollCtl(c: *Ctx, op: u32, fd: i64, events: u32, token: u64) bool {
    const result = ep.ctl(c.epfd, op, fd, events, token);
    if (result == .none) return true;
    c.last_error = result;
    return false;
}

fn backendAdd(c: *Ctx, fd: i64, events: u32, token: u64, socket: bool) bool {
    if (fd < 0) {
        c.last_error = .invalid;
        return false;
    }
    if (c.backend == .epoll) {
        if (!epollCtl(c, ep.ADD, fd, events, token)) return false;
        c.epoll_count += 1;
        return true;
    }
    if (events & ET != 0) {
        c.last_error = .nosupport;
        return false;
    }
    if (c.find(fd) != null) {
        c.last_error = .exists;
        return false;
    }
    // WSAPoll waits on sockets only
    if (is_windows and !socket) {
        c.last_error = .nosupport;
        return false;
    }
    var at: usize = c.table.items.len;
    for (c.table.items, 0..) |e, i| if (e.fd > fd) {
        at = i;
        break;
    };
    c.table.insert(c.allocator, at, .{ .fd = fd, .events = events, .token = token }) catch {
        c.last_error = .nomem;
        return false;
    };
    return true;
}

fn backendModify(c: *Ctx, fd: i64, events: u32, token: u64) bool {
    if (fd < 0) {
        c.last_error = .invalid;
        return false;
    }
    if (c.backend == .epoll) return epollCtl(c, ep.MOD, fd, events, token);
    if (events & ET != 0) {
        c.last_error = .nosupport;
        return false;
    }
    const i = c.find(fd) orelse {
        c.last_error = .notfound;
        return false;
    };
    c.table.items[i].events = events;
    c.table.items[i].token = token;
    return true;
}

fn backendRemove(c: *Ctx, fd: i64) bool {
    if (fd < 0) {
        c.last_error = .invalid;
        return false;
    }
    if (c.backend == .epoll) {
        if (!epollCtl(c, ep.DEL, fd, 0, 0)) return false;
        c.epoll_count -= 1;
        return true;
    }
    const i = c.find(fd) orelse {
        c.last_error = .notfound;
        return false;
    };
    _ = c.table.orderedRemove(i);
    return true;
}

fn suitableMaxEvents(c: *Ctx) i64 {
    const n: i64 = if (c.backend == .epoll) c.epoll_count else @intCast(c.table.items.len);
    return if (n <= 0) 1 else n;
}

// an event a backend reports: the descriptor, and the registration it
// fired for
const Fired = struct { fd: i64, token: u64, revents: u32 };

const Timeout = struct { seconds: u64, nanoseconds: u32 };

// php_poll_timespec_to_ms: capped rather than wrapped, nanoseconds rounded up
fn timeoutMs(timeout: ?Timeout) i32 {
    const t = timeout orelse return -1;
    const max: u64 = std.math.maxInt(i32);
    if (t.seconds >= (max - 1000) / 1000) return std.math.maxInt(i32);
    var ms: u64 = t.seconds * 1000;
    if (t.nanoseconds > 0) ms += (@as(u64, t.nanoseconds) + 999_999) / 1_000_000;
    return @intCast(ms);
}

// the backend's wait; null on failure with c.last_error set
fn backendWait(c: *Ctx, out: []Fired, timeout: ?Timeout) ?usize {
    if (c.backend == .epoll) return ep.wait(c.allocator, c.epfd, out, timeoutMs(timeout), &c.last_error);
    if (c.table.items.len == 0) {
        if (timeout) |t| if (t.seconds > 0 or t.nanoseconds > 0) platform.sleep(t.seconds *| std.time.ns_per_s +| t.nanoseconds);
        return 0;
    }
    const fds = c.allocator.alloc(sys.pollfd, c.table.items.len) catch {
        c.last_error = .nomem;
        return null;
    };
    defer c.allocator.free(fds);
    for (c.table.items, 0..) |e, i| {
        var native: i16 = 0;
        if (e.events & READ != 0) native |= sys.POLL.IN;
        if (e.events & WRITE != 0) native |= sys.POLL.OUT;
        if (!is_windows) {
            if (e.events & ERROR != 0) native |= sys.POLL.ERR;
            if (e.events & HUP != 0) native |= sys.POLL.HUP;
        }
        fds[i] = .{ .fd = platform.socketFromInt(e.fd) orelse return null, .events = native, .revents = 0 };
    }
    const ready = pollFds(fds, timeoutMs(timeout), &c.last_error) orelse return null;
    if (ready == 0) return 0;
    var count: usize = 0;
    var oneshots: std.ArrayListUnmanaged(i64) = .empty;
    defer oneshots.deinit(c.allocator);
    for (fds) |pfd| {
        if (count >= out.len) break;
        if (pfd.revents == 0) continue;
        const fd = platform.socketToInt(pfd.fd);
        const idx = c.find(fd) orelse continue;
        const entry = c.table.items[idx];
        // an invalid descriptor leaves the table unreported
        if (pfd.revents & sys.POLL.NVAL != 0) {
            _ = c.table.orderedRemove(idx);
            continue;
        }
        var events: u32 = 0;
        if (pfd.revents & sys.POLL.IN != 0) events |= READ;
        if (pfd.revents & sys.POLL.OUT != 0) events |= WRITE;
        if (pfd.revents & sys.POLL.ERR != 0) events |= ERROR;
        if (pfd.revents & sys.POLL.HUP != 0) events |= HUP;
        out[count] = .{ .fd = fd, .token = entry.token, .revents = events };
        count += 1;
        if (entry.events & ONESHOT != 0 and events != 0) oneshots.append(c.allocator, fd) catch {};
    }
    for (oneshots.items) |fd| if (c.find(fd)) |idx| {
        _ = c.table.orderedRemove(idx);
    };
    return count;
}

fn pollFds(fds: []sys.pollfd, timeout_ms: i32, err: *PollError) ?usize {
    if (is_windows) {
        return sys.poll(fds, timeout_ms) catch {
            err.* = .system;
            return null;
        };
    } else {
        const rc = std.c.poll(fds.ptr, @intCast(fds.len), timeout_ms);
        if (rc < 0) {
            err.* = errnoError(std.c.errno(rc));
            return null;
        }
        return @intCast(rc);
    }
}

fn destroyCtx(c: *Ctx) void {
    if (c.epfd >= 0) ep.close(c.epfd);
    c.table.deinit(c.allocator);
    c.allocator.destroy(c);
}

// ---- StreamPollHandle --------------------------------------------------------------

fn handleStream(handle: *PhpObject) ?*PhpObject {
    const v = handle.get("__stream");
    return if (v == .resource) v.resource else null;
}

// the stream, while it is still open
fn openStream(handle: *PhpObject) ?*PhpObject {
    const r = handleStream(handle) orelse return null;
    if (!std.mem.eql(u8, r.class_name, "FileHandle") or value_mod.resourceClosed(r)) return null;
    return r;
}

// php_stream_cast(PHP_STREAM_AS_FD_FOR_POLL): the descriptor to poll, with
// php's warning for a stream that has none. filtered streams are polled
// through their descriptor, unlike select's
fn pollDescriptor(ctx: *NativeContext, obj: *PhpObject) RuntimeError!?i64 {
    if (!std.mem.eql(u8, obj.class_name, "FileHandle") or value_mod.resourceClosed(obj)) return null;
    if (fs.fileHandleWrapper(obj)) |w| {
        if (try user_streams.cast(ctx, obj, w, user_streams.CAST_FOR_SELECT, true)) |inner| {
            if (try pollDescriptor(ctx, inner)) |fd| return fd;
        }
        try fs.warnDocref(ctx, "Cannot represent a stream of type user-space as a pollable descriptor", .{});
        return null;
    }
    if (streams.memoryOf(obj) != null) {
        const path = obj.get("__path");
        const label: []const u8 = if (path == .string and std.ascii.startsWithIgnoreCase(path.string.bytes(), "php://temp")) "TEMP" else if (path == .string and std.ascii.startsWithIgnoreCase(path.string.bytes(), "php://memory")) "MEMORY" else "RFC2397";
        try fs.warnDocref(ctx, "Cannot represent a stream of type {s} as a pollable descriptor", .{label});
        return null;
    }
    const fdv = obj.get("__fd");
    if (fdv != .int or fdv.int < 0) return null;
    return fdv.int;
}

fn handleFd(ctx: *NativeContext, handle: *PhpObject) RuntimeError!?i64 {
    const stream = openStream(handle) orelse return null;
    return pollDescriptor(ctx, stream);
}

// the descriptor without the warnings, to tell whether a watcher's handle
// still names the one it was added with
fn quietFd(handle: *PhpObject) ?i64 {
    const stream = openStream(handle) orelse return null;
    if (fs.fileHandleWrapper(stream) != null or streams.memoryOf(stream) != null) return null;
    const fdv = stream.get("__fd");
    if (fdv != .int or fdv.int < 0) return null;
    return fdv.int;
}

fn hasBufferedData(handle: *PhpObject) bool {
    const stream = openStream(handle) orelse return false;
    const s = streams.get(stream) orelse return false;
    return s.buffered() > 0;
}

fn handleConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const stream = try fs.streamArg(ctx, args, .{ .func = stream_handle_class ++ "::__construct" });
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    if (handleStream(this) != null) return throwPlain(ctx, "Error", "StreamPollHandle object is already constructed");
    try this.set(ctx.allocator, "__stream", .{ .resource = stream });
    return NativeResult.scalar(.null);
}

fn handleGetStream(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const r = handleStream(this) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .resource = r });
}

fn handleIsValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisObject(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const stream = openStream(this) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = !(try streams.eof(ctx, stream)) });
}

// ---- watcher registration ------------------------------------------------------------

// a level Read watcher, which buffered stream data reports
fn readsBuffered(w: *W) bool {
    return (w.watched & (READ | ET)) == READ;
}

fn deactivate(w: *W) void {
    w.active = false;
    w.context = null;
    w.context_obj = null;
    w.fd = -1;
}

fn streamWatch(ctx: *NativeContext, stream: *PhpObject, w: *W) RuntimeError!void {
    const s = try streams.of(ctx, stream);
    try s.poll_watchers.append(s.allocator, @intFromPtr(w));
    w.stream = stream;
}

fn streamUnwatch(w: *W) void {
    const stream = w.stream orelse return;
    w.stream = null;
    const s = streams.get(stream) orelse return;
    for (s.poll_watchers.items, 0..) |p, i| if (p == @intFromPtr(w)) {
        _ = s.poll_watchers.swapRemove(i);
        break;
    };
}

// php_io_poll_context_retire_watcher: out of the backend, off its stream,
// inactive, and dropped from the context's table
fn retire(vm: *VM, w: *W) void {
    const c = w.context orelse return;
    const context_obj = w.context_obj;
    const fd = w.fd;
    _ = backendRemove(c, fd);
    streamUnwatch(w);
    deactivate(w);
    const arr = (if (context_obj) |o| watchersOf(o) else null) orelse return;
    const key: PhpArray.Key = .{ .int = fd };
    const held = arr.get(key);
    if (held == .object and held.object == w.obj) {
        arr.remove(key);
        vm.releaseValue(held);
    }
}

// a stream about to close (fclose, or freed): php_io_poll_stream_notify_close
pub fn streamClosing(vm: *VM, stream: *PhpObject) void {
    const s = streams.get(stream) orelse return;
    while (s.poll_watchers.pop()) |p| {
        const w: *W = @ptrFromInt(p);
        w.stream = null;
        w.closed = true;
        retire(vm, w);
    }
}

// a stream's state going away at teardown: its watchers forget it
pub fn streamReleased(s: *streams.Stream) void {
    for (s.poll_watchers.items) |p| {
        const w: *W = @ptrFromInt(p);
        w.stream = null;
    }
    s.poll_watchers.deinit(s.allocator);
    s.poll_watchers = .empty;
}

fn cleanupWatcher(obj: *PhpObject) bool {
    const w = watcherOf(obj) orelse return true;
    streamUnwatch(w);
    obj.native = .{};
    w.allocator.destroy(w);
    return true;
}

fn cleanupContext(obj: *PhpObject) bool {
    const c = ctxOf(obj) orelse return true;
    if (watchersOf(obj)) |arr| for (arr.entries.items) |entry| {
        const w = watcherOfValue(entry.value) orelse continue;
        streamUnwatch(w);
        deactivate(w);
    };
    obj.native = .{};
    destroyCtx(c);
    return true;
}

// the request's leftovers at teardown, contexts first so no watcher points
// at a freed one
pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled) continue;
        if (obj.native.kind == .poll_context) _ = cleanupContext(obj);
    }
    for (objects.items) |obj| {
        if (obj.pooled) continue;
        if (obj.native.kind == .poll_watcher) _ = cleanupWatcher(obj);
    }
}

// ---- events ----------------------------------------------------------------------

// an array of Event cases as bits; 0 for anything else in it
fn eventBits(ctx: *NativeContext, arr: *PhpArray) u32 {
    var bits: u32 = 0;
    for (arr.entries.items) |entry| {
        if (entry.ref != null) return 0;
        const v = entry.value;
        if (v != .object or !ctx.vm.isInstanceOf(v.object.class_name, event_class)) return 0;
        const i = caseIndex(v.object, &event_names) orelse return 0;
        bits |= @as(u32, 1) << @intCast(i);
    }
    return bits;
}

fn eventsArg(ctx: *NativeContext, args: []const Value, comptime func: []const u8, index: usize) RuntimeError!u32 {
    const a = Args.init(ctx, func, args);
    if (index >= args.len or args[index] != .array) return a.typeError(index, "events", "array");
    const bits = eventBits(ctx, args[index].array);
    if (bits == 0) {
        const msg = try std.fmt.allocPrint(ctx.allocator, func ++ "(): Argument #{d} ($events) must be array of Event enums", .{index + 1});
        defer ctx.allocator.free(msg);
        return throwPlain(ctx, "TypeError", msg);
    }
    return bits;
}

fn eventList(ctx: *NativeContext, bits: u32) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (event_names, 0..) |name, i| {
        if (bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
        const case = enumCase(ctx.vm, event_class, name) orelse continue;
        try arr.append(ctx.allocator, .{ .object = case });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// ---- Watcher -----------------------------------------------------------------------

fn thisWatcher(ctx: *NativeContext) ?*W {
    const this = thisObject(ctx) orelse return null;
    return watcherOf(this);
}

fn watcherConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return throwPlain(ctx, "Error", "Cannot directly construct Watcher, use Context::add");
}

fn watcherGetHandle(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const h = this.get("__handle");
    if (h != .object) return NativeResult.scalar(.null);
    return NativeResult.borrowed(h);
}

fn watcherGetWatched(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const w = thisWatcher(ctx) orelse return eventList(ctx, 0);
    return eventList(ctx, w.watched);
}

fn watcherGetTriggered(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const w = thisWatcher(ctx) orelse return eventList(ctx, 0);
    return eventList(ctx, w.triggered);
}

fn watcherGetData(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("__data"));
}

fn watcherHasTriggered(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const event = try Args.init(ctx, watcher_class ++ "::hasTriggered", args).object(0, "event", event_class);
    const w = thisWatcher(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const i = caseIndex(event, &event_names) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = w.triggered & (@as(u32, 1) << @intCast(i)) != 0 });
}

fn watcherIsActive(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const w = thisWatcher(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = w.active });
}

fn modifyEvents(ctx: *NativeContext, w: *W, events: u32) RuntimeError!void {
    const c = w.context orelse return throwPlain(ctx, exc_inactive, "Cannot modify inactive watcher");
    if (!w.active) return throwPlain(ctx, exc_inactive, "Cannot modify inactive watcher");
    // a fired one-shot the backend dropped is added again
    if (!backendModify(c, w.fd, events, w.token)) {
        const readd = c.last_error == .notfound and backendAdd(c, w.fd, events, w.token, isSocketWatcher(w));
        if (!readd) return throwCode(ctx, exc_modify, "Failed to modify watcher in polling system", @intFromEnum(c.last_error));
    }
    w.watched = events;
    w.disarmed = false;
    if (readsBuffered(w)) c.buffered_readers = true;
}

fn isSocketWatcher(w: *W) bool {
    const stream = w.stream orelse return false;
    return fs.isNetStream(stream);
}

fn modifyData(ctx: *NativeContext, w: *W, data: Value) RuntimeError!void {
    if (!w.active) return throwPlain(ctx, exc_inactive, "Cannot modify inactive watcher");
    try w.obj.set(ctx.allocator, "__data", data);
}

fn watcherModify(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const events = try eventsArg(ctx, args, watcher_class ++ "::modify", 0);
    const w = thisWatcher(ctx) orelse return NativeResult.scalar(.null);
    try modifyEvents(ctx, w, events);
    if (args.len > 1) try modifyData(ctx, w, args[1]);
    return NativeResult.scalar(.null);
}

fn watcherModifyEvents(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const events = try eventsArg(ctx, args, watcher_class ++ "::modifyEvents", 0);
    const w = thisWatcher(ctx) orelse return NativeResult.scalar(.null);
    try modifyEvents(ctx, w, events);
    return NativeResult.scalar(.null);
}

fn watcherModifyData(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const w = thisWatcher(ctx) orelse return NativeResult.scalar(.null);
    try modifyData(ctx, w, if (args.len > 0) args[0] else .null);
    return NativeResult.scalar(.null);
}

fn watcherRemove(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const w = thisWatcher(ctx) orelse return NativeResult.scalar(.null);
    if (!w.active or w.context == null) {
        // closing the stream removed it already
        if (w.closed) return NativeResult.scalar(.null);
        return throwPlain(ctx, exc_inactive, "Cannot remove inactive watcher");
    }
    retire(ctx.vm, w);
    return NativeResult.scalar(.null);
}

// ---- Context -----------------------------------------------------------------------

fn thisContext(ctx: *NativeContext) ?*PhpObject {
    const this = thisObject(ctx) orelse return null;
    return if (std.mem.eql(u8, this.class_name, context_class)) this else null;
}

fn contextConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    var backend: Backend = .auto;
    if (args.len > 0) {
        const obj = try Args.init(ctx, context_class ++ "::__construct", args).object(0, "backend", backend_class);
        backend = @enumFromInt(caseIndex(obj, &backend_names) orelse 0);
    }
    const this = thisContext(ctx) orelse return NativeResult.scalar(.null);
    if (ctxOf(this) != null) return throwPlain(ctx, "Error", "Io\\Poll\\Context object is already constructed");
    const resolved = if (backend == .auto) bestBackend() else backend;
    if (!isAvailable(resolved)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Backend {s} not available", .{backend_names[@intFromEnum(backend)]});
        defer ctx.allocator.free(msg);
        return throwPlain(ctx, exc_unavailable, msg);
    }
    const c = try ctx.vm.allocator.create(Ctx);
    c.* = .{ .allocator = ctx.vm.allocator, .backend = resolved };
    if (!initBackend(c)) {
        const code = @intFromEnum(c.last_error);
        destroyCtx(c);
        return throwCode(ctx, exc_init, "Failed to initialize polling context", code);
    }
    this.native = .{ .kind = .poll_context, .ptr = @intFromPtr(c) };
    try this.set(ctx.allocator, "__watchers", .{ .array = try ctx.createArray() });
    return NativeResult.scalar(.null);
}

fn contextGetBackend(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisContext(ctx) orelse return NativeResult.scalar(.null);
    const backend: Backend = if (ctxOf(this)) |c| c.backend else .auto;
    const case = enumCase(ctx.vm, backend_class, backend_names[@intFromEnum(backend)]) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = case });
}

fn contextAdd(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const handle = try Args.init(ctx, context_class ++ "::add", args).object(0, "handle", handle_iface);
    const events = try eventsArg(ctx, args, context_class ++ "::add", 1);
    const this = thisContext(ctx) orelse return NativeResult.scalar(.null);
    const c = ctxOf(this) orelse return NativeResult.scalar(.null);
    const watchers = watchersOf(this) orelse return NativeResult.scalar(.null);

    const fd = (try handleFd(ctx, handle)) orelse return throwPlain(ctx, exc_invalid, "Invalid handle for polling");

    const existing = watchers.get(.{ .int = fd });
    if (watcherOfValue(existing)) |old| {
        const old_handle = old.obj.get("__handle");
        if (old_handle == .object and quietFd(old_handle.object) == fd) return throwPlain(ctx, exc_already, "Handle already added");
        retire(ctx.vm, old);
    }

    const obj = try ctx.createObject(watcher_class);
    const w = try ctx.vm.allocator.create(W);
    c.next_generation +%= 1;
    w.* = .{ .allocator = ctx.vm.allocator, .obj = obj, .watched = events, .token = (@as(u64, c.next_generation) << 32) | @as(u32, @truncate(@as(u64, @bitCast(fd)))) };
    obj.native = .{ .kind = .poll_watcher, .ptr = @intFromPtr(w) };
    try obj.set(ctx.allocator, "__handle", .{ .object = handle });
    try obj.set(ctx.allocator, "__data", if (args.len > 2) args[2] else .null);

    const stream = openStream(handle);
    const socket = if (stream) |s| fs.isNetStream(s) else false;
    if (!backendAdd(c, fd, events, w.token, socket)) {
        // the watcher was made first, and goes when the call ends
        obj.retain();
        defer ctx.vm.releaseValue(.{ .object = obj });
        if (c.last_error == .exists) return throwPlain(ctx, exc_already, "Handle already added");
        return throwCode(ctx, exc_add, "Failed to add handle", @intFromEnum(c.last_error));
    }

    try watchers.set(ctx.allocator, .{ .int = fd }, .{ .object = obj });
    w.active = true;
    w.context = c;
    w.context_obj = this;
    w.fd = fd;
    if (readsBuffered(w)) c.buffered_readers = true;
    if (stream) |s| try streamWatch(ctx, s, w);
    return NativeResult.borrowed(.{ .object = obj });
}

// the watcher a backend event names, if it is still the one registered
fn firedWatcher(watchers: *PhpArray, f: Fired) ?*W {
    const w = watcherOfValue(watchers.get(.{ .int = f.fd })) orelse return null;
    return if (w.token == f.token) w else null;
}

fn contextWait(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, context_class ++ "::wait", args);
    const timeout_obj = try a.objectOrNull(0, "timeout", duration.class_name);
    const max_arg = if (args.len > 1) try a.longOrNull(1, "maxEvents") else null;
    const this = thisContext(ctx) orelse return NativeResult.scalar(.null);

    var timeout: ?Timeout = null;
    if (timeout_obj) |t| {
        const span = duration.spanOf(t);
        if (span.negative) return a.valueError(0, "timeout", "must not be negative");
        timeout = .{ .seconds = span.seconds, .nanoseconds = span.nanoseconds };
    }
    const c = ctxOf(this) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const watchers = watchersOf(this) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    var max_events: i64 = undefined;
    if (max_arg) |m| {
        if (m <= 0) return a.valueError(1, "maxEvents", "must be greater than 0");
        if (m > std.math.maxInt(i32)) return a.valueError(1, "maxEvents", "must be less than or equal to 2147483647");
        max_events = m;
    } else {
        max_events = suitableMaxEvents(c);
    }
    const max: usize = @intCast(max_events);

    // buffered watchers go first, then a non-blocking backend check
    var buffered: std.ArrayListUnmanaged(*W) = .empty;
    defer buffered.deinit(ctx.allocator);
    if (c.buffered_readers) {
        for (watchers.entries.items) |entry| {
            const w = watcherOfValue(entry.value) orelse continue;
            if (w.disarmed or !readsBuffered(w)) continue;
            const h = w.obj.get("__handle");
            if (h != .object or !hasBufferedData(h.object)) continue;
            try buffered.append(ctx.allocator, w);
            if (buffered.items.len == max) break;
        }
    }

    var fired: []Fired = &.{};
    defer if (fired.len > 0) ctx.allocator.free(fired);
    var count: usize = 0;
    if (buffered.items.len < max) {
        fired = try ctx.allocator.alloc(Fired, max - buffered.items.len);
        const wait_timeout: ?Timeout = if (buffered.items.len > 0) Timeout{ .seconds = 0, .nanoseconds = 0 } else timeout;
        // what the script printed is out before it waits, as php's cli has it
        if (timeoutMs(wait_timeout) != 0) ctx.vm.flushOutputToStdout();
        if (backendWait(c, fired, wait_timeout)) |n| {
            count = n;
        } else if (buffered.items.len == 0 or c.last_error != .interrupted) {
            return throwCode(ctx, exc_wait, "Poll wait failed", @intFromEnum(c.last_error));
        }
    }

    const result = try ctx.createArray();
    for (buffered.items) |w| {
        w.triggered = READ;
        w.reported = true;
        try result.append(ctx.allocator, .{ .object = w.obj });
    }
    for (fired[0..count]) |f| {
        const w = firedWatcher(watchers, f) orelse continue;
        if (w.watched & ONESHOT != 0) w.disarmed = true;
        if (w.reported) {
            w.triggered |= f.revents;
            continue;
        }
        w.triggered = f.revents;
        try result.append(ctx.allocator, .{ .object = w.obj });
    }
    // a buffer-only one-shot is still armed in the backend
    for (buffered.items) |w| {
        w.reported = false;
        if (w.watched & ONESHOT != 0 and !w.disarmed) {
            w.disarmed = true;
            _ = backendRemove(c, w.fd);
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}
