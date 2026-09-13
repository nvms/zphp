// worker threads for php code: a Zphp\Pool owns os threads that each run an
// isolated VM, tasks are named callables with transferable arguments, and a
// Zphp\Future carries the result or the exception back. values cross as
// serialized bytes and are materialized in the receiving VM
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const NativeHandle = value_mod.NativeHandle;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const serialize = @import("serialize.zig");
const network = @import("network.zig");
const platform = @import("../platform.zig");
const extension = @import("../extension.zig");

const pool_class = "Zphp\\Pool";
const future_class = "Zphp\\Future";
const task_class = "Zphp\\Task";
const pool_exception = "Zphp\\PoolException";
const task_exception = "Zphp\\TaskException";
const cancelled_exception = "Zphp\\CancelledException";
const timeout_exception = "Zphp\\TimeoutException";
const transfer_exception = "Zphp\\TransferException";

const default_queue: usize = 1024;

// ---------------------------------------------------------------------------
// tasks

const TaskState = enum(u8) { queued, running, done, failed, cancelled };

const Failure = struct {
    class_name: []u8,
    message: []u8,
    code: i64,
    file: []u8,
    line: i64,
};

const Task = struct {
    id: u64,
    pool: *Pool,
    callable: []u8,
    args: []u8,
    state: TaskState = .queued,
    result: ?[]u8 = null,
    failure: ?Failure = null,
    fatal: ?[]u8 = null,
    cancel_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    // one reference for the Future wrapper, one for the pool until delivery
    refs: std.atomic.Value(u32) = std.atomic.Value(u32).init(2),
    future: ?*PhpObject = null,
    delivered: bool = false,
    mutex: std.Thread.Mutex = .{},
    finished: std.Thread.Condition = .{},

    fn release(t: *Task) void {
        if (t.refs.fetchSub(1, .acq_rel) == 1) t.destroy();
    }

    fn destroy(t: *Task) void {
        const pool = t.pool;
        const a = pool.allocator;
        a.free(t.callable);
        a.free(t.args);
        if (t.result) |r| a.free(r);
        if (t.failure) |f| {
            a.free(f.class_name);
            a.free(f.message);
            a.free(f.file);
        }
        if (t.fatal) |m| a.free(m);
        a.destroy(t);
        pool.release();
    }

    fn settled(t: *Task) bool {
        return t.state == .done or t.state == .failed or t.state == .cancelled;
    }

    // blocks until the task settles or the timeout passes
    fn wait(t: *Task, timeout_ns: ?u64) bool {
        t.mutex.lock();
        defer t.mutex.unlock();
        if (timeout_ns) |total| {
            const deadline = std.time.nanoTimestamp() + @as(i128, total);
            while (!t.settled()) {
                const now = std.time.nanoTimestamp();
                if (now >= deadline) return false;
                t.finished.timedWait(&t.mutex, @intCast(deadline - now)) catch return t.settled();
            }
            return true;
        }
        while (!t.settled()) t.finished.wait(&t.mutex);
        return true;
    }
};

threadlocal var current_task: ?*Task = null;
threadlocal var current_worker: i64 = -1;

// ---------------------------------------------------------------------------
// the bounded queue between the submitting thread and the workers

const Queue = struct {
    items: []*Task,
    head: usize = 0,
    len: usize = 0,
    closed: bool = false,
    mutex: std.Thread.Mutex = .{},
    not_empty: std.Thread.Condition = .{},
    not_full: std.Thread.Condition = .{},

    const PushResult = enum { ok, full, closed };

    fn push(q: *Queue, task: *Task, block: bool) PushResult {
        q.mutex.lock();
        defer q.mutex.unlock();
        while (q.len == q.items.len and !q.closed) {
            if (!block) return .full;
            q.not_full.wait(&q.mutex);
        }
        if (q.closed) return .closed;
        q.items[(q.head + q.len) % q.items.len] = task;
        q.len += 1;
        q.not_empty.signal();
        return .ok;
    }

    fn pop(q: *Queue) ?*Task {
        q.mutex.lock();
        defer q.mutex.unlock();
        while (q.len == 0 and !q.closed) q.not_empty.wait(&q.mutex);
        if (q.len == 0) return null;
        const task = q.items[q.head];
        q.head = (q.head + 1) % q.items.len;
        q.len -= 1;
        q.not_full.signal();
        return task;
    }

    // stops producers and lets every worker drain what is left
    fn close(q: *Queue) void {
        q.mutex.lock();
        defer q.mutex.unlock();
        q.closed = true;
        q.not_empty.broadcast();
        q.not_full.broadcast();
    }

    fn drop(q: *Queue, task: *Task) bool {
        q.mutex.lock();
        defer q.mutex.unlock();
        var i: usize = 0;
        while (i < q.len) : (i += 1) {
            const at = (q.head + i) % q.items.len;
            if (q.items[at] != task) continue;
            var j = i;
            while (j + 1 < q.len) : (j += 1) {
                q.items[(q.head + j) % q.items.len] = q.items[(q.head + j + 1) % q.items.len];
            }
            q.len -= 1;
            q.not_full.signal();
            return true;
        }
        return false;
    }
};

// ---------------------------------------------------------------------------
// the pool

const Worker = struct {
    pool: *Pool,
    index: usize,
    thread: ?std.Thread = null,
};

const StartState = enum { starting, running, failed };

const Pool = struct {
    allocator: std.mem.Allocator,
    owner: *VM,
    workers: []Worker,
    queue: Queue,
    bootstrap: ?[]u8,
    file_loader: ?*const vm_mod.FileLoader,
    mutex: std.Thread.Mutex = .{},
    changed: std.Thread.Condition = .{},
    start_state: StartState = .starting,
    started: usize = 0,
    start_error: ?[]u8 = null,
    shutting_down: bool = false,
    running_tasks: usize = 0,
    completed: std.ArrayListUnmanaged(*Task) = .{},
    next_id: u64 = 1,
    wake: [2]std.posix.socket_t,
    readiness: ?*PhpObject = null,
    // the php object plus every live task hold the pool; a future can outlive
    // the pool that made it
    refs: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),

    fn retain(pool: *Pool) void {
        _ = pool.refs.fetchAdd(1, .acq_rel);
    }

    fn release(pool: *Pool) void {
        if (pool.refs.fetchSub(1, .acq_rel) == 1) pool.free();
    }

    fn create(allocator: std.mem.Allocator, owner: *VM, workers: usize, bootstrap_path: ?[]const u8, queue_size: usize) !*Pool {
        const pool = try allocator.create(Pool);
        errdefer allocator.destroy(pool);
        const items = try allocator.alloc(*Task, queue_size);
        errdefer allocator.free(items);
        const slots = try allocator.alloc(Worker, workers);
        errdefer allocator.free(slots);
        const wake = try platform.socketPair();
        pool.* = .{
            .allocator = allocator,
            .owner = owner,
            .workers = slots,
            .queue = .{ .items = items },
            .bootstrap = if (bootstrap_path) |b| try allocator.dupe(u8, b) else null,
            .file_loader = owner.file_loader,
            .wake = wake,
        };
        for (slots, 0..) |*w, i| w.* = .{ .pool = pool, .index = i };
        return pool;
    }

    // spawns every worker and waits until all have bootstrapped or one failed
    fn start(pool: *Pool) ?[]const u8 {
        for (pool.workers) |*w| {
            w.thread = std.Thread.spawn(.{}, workerMain, .{w}) catch {
                pool.reportStart("could not start a worker thread");
                break;
            };
        }
        pool.mutex.lock();
        while (pool.start_state == .starting and pool.started < pool.workers.len) pool.changed.wait(&pool.mutex);
        if (pool.start_state == .starting) pool.start_state = .running;
        const failure = pool.start_error;
        pool.mutex.unlock();
        return failure;
    }

    fn reportStart(pool: *Pool, failure: ?[]const u8) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();
        if (failure) |msg| {
            if (pool.start_error == null) pool.start_error = pool.allocator.dupe(u8, msg) catch null;
            pool.start_state = .failed;
        } else {
            pool.started += 1;
        }
        pool.changed.broadcast();
    }

    fn nextId(pool: *Pool) u64 {
        pool.mutex.lock();
        defer pool.mutex.unlock();
        const id = pool.next_id;
        pool.next_id += 1;
        return id;
    }

    fn complete(pool: *Pool, task: *Task) void {
        pool.mutex.lock();
        pool.completed.append(pool.allocator, task) catch {};
        pool.changed.broadcast();
        pool.mutex.unlock();
        _ = platform.send(pool.wake[1], "x") catch {};
    }

    // a future awaited directly leaves the completion list: the pool's
    // reference goes with it, so only the future keeps the task alive
    fn deliverDirect(pool: *Pool, task: *Task) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();
        for (pool.completed.items, 0..) |candidate, i| {
            if (candidate != task) continue;
            _ = pool.completed.orderedRemove(i);
            var byte: [1]u8 = undefined;
            _ = platform.recv(pool.wake[0], &byte) catch {};
            task.release();
            return;
        }
    }

    // next completed task, in completion order; null on timeout or when
    // nothing can complete any more
    fn collect(pool: *Pool, timeout_ns: ?u64) ?*Task {
        pool.mutex.lock();
        defer pool.mutex.unlock();
        const deadline: ?i128 = if (timeout_ns) |t| std.time.nanoTimestamp() + @as(i128, t) else null;
        while (true) {
            while (pool.completed.items.len == 0) {
                if (pool.queue.len == 0 and pool.running_tasks == 0) return null;
                if (deadline) |d| {
                    const now = std.time.nanoTimestamp();
                    if (now >= d) return null;
                    pool.changed.timedWait(&pool.mutex, @intCast(d - now)) catch {};
                } else pool.changed.wait(&pool.mutex);
            }
            while (pool.completed.items.len > 0) {
                const task = pool.completed.orderedRemove(0);
                var byte: [1]u8 = undefined;
                _ = platform.recv(pool.wake[0], &byte) catch {};
                task.mutex.lock();
                const fresh = !task.delivered;
                task.delivered = true;
                task.mutex.unlock();
                if (fresh) {
                    if (task.future == null) _ = task.refs.fetchAdd(1, .acq_rel);
                    task.release();
                    return task;
                }
                task.release();
            }
        }
    }

    // stop accepting work, cancel what is queued, wait for running tasks
    fn shutdown(pool: *Pool, timeout_ns: ?u64) bool {
        pool.mutex.lock();
        const already = pool.shutting_down;
        pool.shutting_down = true;
        pool.mutex.unlock();
        if (!already) {
            pool.queue.mutex.lock();
            while (pool.queue.len > 0) {
                const task = pool.queue.items[pool.queue.head];
                pool.queue.head = (pool.queue.head + 1) % pool.queue.items.len;
                pool.queue.len -= 1;
                markCancelled(task);
                pool.queue.mutex.unlock();
                pool.complete(task);
                pool.queue.mutex.lock();
            }
            pool.queue.mutex.unlock();
            pool.queue.close();
        }
        if (timeout_ns) |t| {
            pool.mutex.lock();
            defer pool.mutex.unlock();
            const deadline = std.time.nanoTimestamp() + @as(i128, t);
            while (pool.running_tasks > 0) {
                const now = std.time.nanoTimestamp();
                if (now >= deadline) return false;
                pool.changed.timedWait(&pool.mutex, @intCast(deadline - now)) catch {};
            }
        }
        pool.join();
        return true;
    }

    fn join(pool: *Pool) void {
        for (pool.workers) |*w| {
            if (w.thread) |t| t.join();
            w.thread = null;
        }
    }

    // the php side is done with the pool: stop the workers and drop the
    // completion list's task references; memory goes when the last task does
    fn destroy(pool: *Pool) void {
        _ = pool.shutdown(null);
        pool.mutex.lock();
        const leftover = pool.completed.toOwnedSlice(pool.allocator) catch &.{};
        pool.mutex.unlock();
        for (leftover) |task| task.release();
        pool.allocator.free(leftover);
        pool.release();
    }

    fn free(pool: *Pool) void {
        pool.completed.deinit(pool.allocator);
        if (pool.readiness == null) platform.closeSocket(platform.socketToInt(pool.wake[0]));
        platform.closeSocket(platform.socketToInt(pool.wake[1]));
        pool.allocator.free(pool.queue.items);
        pool.allocator.free(pool.workers);
        if (pool.bootstrap) |b| pool.allocator.free(b);
        if (pool.start_error) |e| pool.allocator.free(e);
        pool.allocator.destroy(pool);
    }
};

fn markCancelled(task: *Task) void {
    task.mutex.lock();
    defer task.mutex.unlock();
    if (!task.settled()) task.state = .cancelled;
    task.finished.broadcast();
}

// ---------------------------------------------------------------------------
// the worker thread

fn workerMain(w: *Worker) void {
    const pool = w.pool;
    current_worker = @intCast(w.index);
    const vm = VM.initOnHeap(pool.allocator) catch {
        pool.reportStart("worker: out of memory");
        return;
    };
    var boot_result: ?*@import("../pipeline/compiler.zig").CompileResult = null;
    defer if (boot_result) |r| {
        r.deinit();
        pool.allocator.destroy(r);
    };
    defer {
        vm.deinit();
        pool.allocator.destroy(vm);
    }
    vm.file_loader = pool.file_loader;
    vm.installHooks();
    if (pool.bootstrap) |path| {
        boot_result = bootstrap(vm, pool, path) orelse return;
    }
    pool.reportStart(null);
    while (pool.queue.pop()) |task| runTask(vm, task);
}

fn bootstrap(vm: *VM, pool: *Pool, path: []const u8) ?*@import("../pipeline/compiler.zig").CompileResult {
    const loader = vm.file_loader orelse {
        pool.reportStart("bootstrap: no file loader");
        return null;
    };
    var buf: [1024]u8 = undefined;
    const result = loader(path, vm.allocator, vm) orelse {
        const msg = std.fmt.bufPrint(&buf, "bootstrap script {s} could not be compiled", .{path}) catch "bootstrap script could not be compiled";
        pool.reportStart(msg);
        return null;
    };
    vm.interpret(result) catch {
        const msg = describeError(vm, &buf) orelse "bootstrap script failed";
        flushOutput(vm);
        pool.reportStart(msg);
        result.deinit();
        pool.allocator.destroy(result);
        return null;
    };
    flushOutput(vm);
    return result;
}

fn describeError(vm: *VM, buf: []u8) ?[]const u8 {
    if (vm.pending_exception) |exc| {
        if (exc == .object) {
            const message = exc.object.get("message");
            const text = if (message == .string) message.string.bytes() else "";
            return std.fmt.bufPrint(buf, "{s}: {s}", .{ exc.object.class_name, text }) catch text;
        }
    }
    return vm.error_msg;
}

fn flushOutput(vm: *VM) void {
    if (vm.output.items.len == 0) return;
    platform.writeStdout(vm.output.items);
    vm.output.clearRetainingCapacity();
}

fn runTask(vm: *VM, task: *Task) void {
    const pool = task.pool;
    task.mutex.lock();
    if (task.state == .cancelled) {
        task.mutex.unlock();
        pool.complete(task);
        return;
    }
    task.state = .running;
    task.mutex.unlock();
    pool.mutex.lock();
    pool.running_tasks += 1;
    pool.mutex.unlock();

    current_task = task;
    defer current_task = null;
    extension.beginRequest(vm) catch {};
    var ctx = vm.makeContext(task_class);
    execute(&ctx, task);
    extension.endRequest(vm);
    vm.pending_exception = null;
    vm.error_msg = null;
    vm.drainPendingDestruct();
    flushOutput(vm);

    pool.mutex.lock();
    pool.running_tasks -= 1;
    pool.mutex.unlock();
    pool.complete(task);
}

fn execute(ctx: *NativeContext, task: *Task) void {
    const callable = hold(serialize.unserializeFromString(ctx, task.callable) orelse return settleFatal(task, "the callable did not transfer"));
    const args_value = hold(serialize.unserializeFromString(ctx, task.args) orelse return settleFatal(task, "the arguments did not transfer"));
    var args: [64]Value = undefined;
    var count: usize = 0;
    if (args_value == .array) {
        for (args_value.array.entries.items) |entry| {
            if (count == args.len) break;
            args[count] = entry.value;
            count += 1;
        }
    }
    defer ctx.vm.releaseValue(callable);
    defer ctx.vm.releaseValue(args_value);
    const result = ctx.invokeCallable(callable, args[0..count]) catch {
        settleFailure(ctx.vm, task, callable);
        return;
    };
    // the call hands back its reference the way the interpreter receives a
    // native result: strings need one more retain, containers are ours
    const owned = NativeResult.share(result).value;
    defer ctx.vm.releaseValue(owned);
    const bytes = serialize.serializeToString(ctx, result) catch {
        settleFatal(task, "the result could not be transferred back");
        return;
    };
    defer bytes.value.string.release();
    const copy = task.pool.allocator.dupe(u8, bytes.value.string.bytes()) catch return settleFatal(task, "out of memory");
    task.mutex.lock();
    defer task.mutex.unlock();
    task.result = copy;
    task.state = .done;
    task.finished.broadcast();
}

// containers come out of unserialize at refcount 0, the way the interpreter
// receives them before its push retains; take that reference so the
// release below actually queues them
fn hold(v: Value) Value {
    switch (v) {
        .array => |arr| VM.arrayRetain(arr),
        .object => |obj| VM.objRetain(obj),
        else => {},
    }
    return v;
}

fn settleFatal(task: *Task, msg: []const u8) void {
    task.mutex.lock();
    defer task.mutex.unlock();
    task.fatal = task.pool.allocator.dupe(u8, msg) catch null;
    task.state = .failed;
    task.finished.broadcast();
}

// callByName fails without an exception when the name resolves to nothing
fn settleUndefined(task: *Task, callable: Value) void {
    const a = task.pool.allocator;
    var buf: [600]u8 = undefined;
    const message = switch (callable) {
        .string => |s| std.fmt.bufPrint(&buf, "Call to undefined function {s}()", .{s.bytes()}) catch "Call to undefined function",
        .array => |arr| std.fmt.bufPrint(&buf, "Call to undefined method {s}::{s}()", .{ arr.entries.items[0].value.string.bytes(), arr.entries.items[1].value.string.bytes() }) catch "Call to undefined method",
        else => "the task failed",
    };
    const failure = Failure{
        .class_name = a.dupe(u8, "Error") catch return settleFatal(task, "out of memory"),
        .message = a.dupe(u8, message) catch return settleFatal(task, "out of memory"),
        .code = 0,
        .file = a.dupe(u8, "") catch return settleFatal(task, "out of memory"),
        .line = 0,
    };
    task.mutex.lock();
    defer task.mutex.unlock();
    task.failure = failure;
    task.state = .failed;
    task.finished.broadcast();
}

// the thrown object stays in the worker; its identity crosses as text
fn settleFailure(vm: *VM, task: *Task, callable: Value) void {
    const a = task.pool.allocator;
    const exc = vm.pending_exception orelse {
        if (vm.error_msg) |msg| return settleFatal(task, msg);
        return settleUndefined(task, callable);
    };
    if (exc != .object) return settleFatal(task, "the task failed");
    const obj = exc.object;
    const message = obj.get("message");
    const code = obj.get("code");
    const file = obj.get("file");
    const line = obj.get("line");
    const failure = Failure{
        .class_name = a.dupe(u8, obj.class_name) catch return settleFatal(task, "out of memory"),
        .message = a.dupe(u8, if (message == .string) message.string.bytes() else "") catch return settleFatal(task, "out of memory"),
        .code = if (code == .int) code.int else 0,
        .file = a.dupe(u8, if (file == .string) file.string.bytes() else "") catch return settleFatal(task, "out of memory"),
        .line = if (line == .int) line.int else 0,
    };
    task.mutex.lock();
    defer task.mutex.unlock();
    task.failure = failure;
    task.state = .failed;
    task.finished.broadcast();
}

// ---------------------------------------------------------------------------
// transfer rules, checked in the caller so the error names the path

const TransferCheck = struct {
    ctx: *NativeContext,
    path: std.ArrayListUnmanaged(u8) = .{},

    fn refuse(self: *TransferCheck, what: []const u8) RuntimeError {
        const msg = try std.fmt.allocPrint(self.ctx.allocator, "{s} cannot be transferred to a worker (at {s})", .{ what, self.path.items });
        try self.ctx.vm.strings.append(self.ctx.allocator, msg);
        try self.ctx.vm.setPendingException(transfer_exception, msg);
        return error.RuntimeError;
    }

    fn check(self: *TransferCheck, v: Value) RuntimeError!void {
        switch (v) {
            .null, .bool, .int, .float => {},
            .string => |s| if (std.mem.startsWith(u8, s.bytes(), "__closure")) return self.refuse("a Closure"),
            .array => |arr| {
                const mark = self.path.items.len;
                for (arr.entries.items) |entry| {
                    try self.path.append(self.ctx.allocator, '[');
                    switch (entry.key) {
                        .int => |i| try self.path.writer(self.ctx.allocator).print("{d}", .{i}),
                        .string => |k| try self.path.appendSlice(self.ctx.allocator, k.bytes()),
                    }
                    try self.path.append(self.ctx.allocator, ']');
                    try self.check(if (entry.ref) |cell| cell.* else entry.value);
                    self.path.shrinkRetainingCapacity(mark);
                }
            },
            .object => |obj| {
                if (obj.native.kind != .none) return self.refuse("an object backed by a native handle");
                if (std.mem.eql(u8, obj.class_name, pool_class) or std.mem.eql(u8, obj.class_name, future_class)) return self.refuse("a pool or future");
                const mark = self.path.items.len;
                var it = obj.properties.iterator();
                while (it.next()) |entry| {
                    try self.path.appendSlice(self.ctx.allocator, "->");
                    try self.path.appendSlice(self.ctx.allocator, entry.key_ptr.*);
                    try self.check(entry.value_ptr.*);
                    self.path.shrinkRetainingCapacity(mark);
                }
                if (obj.slots) |slots| for (slots) |slot| try self.check(slot);
            },
            .generator => return self.refuse("a Generator"),
            .fiber => return self.refuse("a Fiber"),
        }
    }
};

fn checkTransferable(ctx: *NativeContext, v: Value, root: []const u8) RuntimeError!void {
    var tc = TransferCheck{ .ctx = ctx };
    defer tc.path.deinit(ctx.allocator);
    try tc.path.appendSlice(ctx.allocator, root);
    try tc.check(v);
}

fn serializedCopy(ctx: *NativeContext, v: Value, allocator: std.mem.Allocator) RuntimeError![]u8 {
    const bytes = try serialize.serializeToString(ctx, v);
    defer bytes.value.string.release();
    return allocator.dupe(u8, bytes.value.string.bytes());
}

// ---------------------------------------------------------------------------
// php surface

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn throwNamed(ctx: *NativeContext, class_name: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    try ctx.vm.strings.append(ctx.allocator, msg);
    try ctx.vm.setPendingException(class_name, msg);
    return error.RuntimeError;
}

fn poolOf(ctx: *NativeContext, obj: *PhpObject) RuntimeError!*Pool {
    const pool = obj.native.get(Pool, .pool) orelse return throwNamed(ctx, pool_exception, "the pool is not running", .{});
    if (pool.owner != ctx.vm) return throwNamed(ctx, pool_exception, "a pool belongs to the thread that created it", .{});
    return pool;
}

fn taskOf(obj: *PhpObject) ?*Task {
    return obj.native.get(Task, .future);
}

fn optionalSeconds(v: Value) ?u64 {
    return switch (v) {
        .int => |i| if (i < 0) null else @as(u64, @intCast(i)) * std.time.ns_per_s,
        .float => |f| if (f < 0) null else @as(u64, @intFromFloat(f * @as(f64, @floatFromInt(std.time.ns_per_s)))),
        else => null,
    };
}

fn poolConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cpu_count: usize = std.Thread.getCpuCount() catch 1;
    var workers: usize = @max(1, cpu_count);
    if (args.len >= 1 and args[0] != .null) {
        if (args[0] != .int or args[0].int < 1) return throwNamed(ctx, pool_exception, "workers must be a positive integer", .{});
        workers = @intCast(args[0].int);
    }
    var bootstrap_path: ?[]const u8 = null;
    if (args.len >= 2 and args[1] != .null) {
        if (args[1] != .string) return throwNamed(ctx, pool_exception, "bootstrap must be a file path", .{});
        bootstrap_path = args[1].string.bytes();
        std.fs.cwd().access(bootstrap_path.?, .{}) catch return throwNamed(ctx, pool_exception, "bootstrap script {s} does not exist", .{bootstrap_path.?});
    }
    var queue_size: usize = default_queue;
    if (args.len >= 3 and args[2] != .null) {
        if (args[2] != .int or args[2].int < 1) return throwNamed(ctx, pool_exception, "queue must be a positive integer", .{});
        queue_size = @intCast(args[2].int);
    }
    const pool = Pool.create(ctx.allocator, ctx.vm, workers, bootstrap_path, queue_size) catch return throwNamed(ctx, pool_exception, "could not create the pool", .{});
    obj.native = .{ .kind = .pool, .ptr = @intFromPtr(pool) };
    const failure = pool.start();
    if (failure) |msg| {
        const copy = try ctx.allocator.dupe(u8, msg);
        try ctx.vm.strings.append(ctx.allocator, copy);
        pool.destroy();
        obj.native = .{};
        try ctx.vm.setPendingException(pool_exception, copy);
        return error.RuntimeError;
    }
    return NativeResult.scalar(.null);
}

fn submitTask(ctx: *NativeContext, args: []const Value, block: bool) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pool = try poolOf(ctx, obj);
    flushOutput(ctx.vm);
    if (args.len < 1) return throwNamed(ctx, pool_exception, "submit() needs a callable", .{});
    const callable = args[0];
    const valid = switch (callable) {
        .string => |s| !std.mem.startsWith(u8, s.bytes(), "__closure"),
        .array => |arr| arr.entries.items.len == 2 and arr.entries.items[0].value == .string and arr.entries.items[1].value == .string,
        else => false,
    };
    if (!valid) return throwNamed(ctx, transfer_exception, "tasks are named callables: a function name, 'Class::method', or [class, method]", .{});
    const task_args: Value = if (args.len >= 2) args[1] else .{ .array = try ctx.createArray() };
    if (task_args != .array) return throwNamed(ctx, pool_exception, "arguments must be an array", .{});
    try checkTransferable(ctx, task_args, "args");
    pool.mutex.lock();
    const closed = pool.shutting_down;
    pool.mutex.unlock();
    if (closed) return throwNamed(ctx, pool_exception, "the pool is shutting down", .{});

    const task = try pool.allocator.create(Task);
    errdefer pool.allocator.destroy(task);
    task.* = .{ .id = pool.nextId(), .pool = pool, .callable = &.{}, .args = &.{} };
    pool.retain();
    errdefer pool.release();
    task.callable = try serializedCopy(ctx, callable, pool.allocator);
    errdefer pool.allocator.free(task.callable);
    task.args = try serializedCopy(ctx, task_args, pool.allocator);
    errdefer pool.allocator.free(task.args);

    switch (pool.queue.push(task, block)) {
        .ok => {},
        .full => {
            pool.allocator.free(task.callable);
            pool.allocator.free(task.args);
            pool.allocator.destroy(task);
            pool.release();
            return NativeResult.scalar(.null);
        },
        .closed => {
            pool.allocator.free(task.callable);
            pool.allocator.free(task.args);
            pool.allocator.destroy(task);
            pool.release();
            return throwNamed(ctx, pool_exception, "the pool is shutting down", .{});
        },
    }
    const future = try ctx.createObject(future_class);
    future.native = .{ .kind = .future, .ptr = @intFromPtr(task) };
    task.future = future;
    return NativeResult.borrowed(.{ .object = future });
}

fn poolSubmit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return submitTask(ctx, args, true);
}

fn poolTrySubmit(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return submitTask(ctx, args, false);
}

fn poolCollect(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pool = try poolOf(ctx, obj);
    const timeout = if (args.len >= 1) optionalSeconds(args[0]) else null;
    flushOutput(ctx.vm);
    const task = pool.collect(timeout) orelse return NativeResult.scalar(.null);
    if (task.future) |future| return NativeResult.borrowed(.{ .object = future });
    const future = try ctx.createObject(future_class);
    future.native = .{ .kind = .future, .ptr = @intFromPtr(task) };
    task.future = future;
    return NativeResult.borrowed(.{ .object = future });
}

fn poolReadiness(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pool = try poolOf(ctx, obj);
    if (pool.readiness) |stream| return NativeResult.borrowed(.{ .object = stream });
    const stream = network.socketStream(ctx, pool.wake[0]) catch return error.OutOfMemory;
    try stream.set(ctx.allocator, "__shared", .{ .bool = true });
    pool.readiness = stream;
    return NativeResult.borrowed(.{ .object = stream });
}

fn poolShutdown(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pool = obj.native.get(Pool, .pool) orelse return NativeResult.scalar(.{ .bool = true });
    const timeout = if (args.len >= 1) optionalSeconds(args[0]) else null;
    flushOutput(ctx.vm);
    return NativeResult.scalar(.{ .bool = pool.shutdown(timeout) });
}

fn poolWorkers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pool = try poolOf(ctx, obj);
    return NativeResult.scalar(.{ .int = @intCast(pool.workers.len) });
}

fn futureIsDone(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const task = taskOf(obj) orelse return NativeResult.scalar(.{ .bool = true });
    task.mutex.lock();
    defer task.mutex.unlock();
    return NativeResult.scalar(.{ .bool = task.settled() });
}

fn futureAwait(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const task = taskOf(obj) orelse return throwNamed(ctx, task_exception, "the future has no task", .{});
    const timeout = if (args.len >= 1) optionalSeconds(args[0]) else null;
    flushOutput(ctx.vm);
    if (!task.wait(timeout)) return throwNamed(ctx, timeout_exception, "the task did not complete in time", .{});
    task.mutex.lock();
    const state = task.state;
    const first = !task.delivered;
    task.delivered = true;
    task.mutex.unlock();
    if (first) task.pool.deliverDirect(task);
    switch (state) {
        .done => {
            // materialized once; later awaits read the value kept on the future
            if (task.result) |bytes| {
                const v = serialize.unserializeFromString(ctx, bytes) orelse return throwNamed(ctx, task_exception, "the result did not transfer", .{});
                // the store takes its own reference; the one unserialize handed over goes
                try obj.set(ctx.allocator, "__result", v);
                if (v == .string) v.string.release();
                task.pool.allocator.free(bytes);
                task.result = null;
            }
            return NativeResult.share(obj.get("__result"));
        },
        .cancelled => return throwNamed(ctx, cancelled_exception, "the task was cancelled", .{}),
        .failed => return rethrow(ctx, task),
        else => unreachable,
    }
}

fn rethrow(ctx: *NativeContext, task: *Task) RuntimeError {
    if (task.failure) |f| {
        const known = ctx.vm.classes.contains(f.class_name) and ctx.vm.isInstanceOf(f.class_name, "Throwable");
        if (known) {
            const msg = try ctx.allocator.dupe(u8, f.message);
            try ctx.vm.strings.append(ctx.allocator, msg);
            try ctx.vm.setPendingException(f.class_name, msg);
        } else {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}: {s}", .{ f.class_name, f.message });
            try ctx.vm.strings.append(ctx.allocator, msg);
            try ctx.vm.setPendingException(task_exception, msg);
        }
        const exc = ctx.vm.pending_exception.?.object;
        try exc.set(ctx.allocator, "code", .{ .int = f.code });
        if (f.file.len > 0) try exc.set(ctx.allocator, "file", .{ .string = Value.String.borrowed(try ctx.createString(f.file)) });
        try exc.set(ctx.allocator, "line", .{ .int = f.line });
        return error.RuntimeError;
    }
    return throwNamed(ctx, task_exception, "{s}", .{task.fatal orelse "the task failed"});
}

fn futureCancel(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const task = taskOf(obj) orelse return NativeResult.scalar(.{ .bool = false });
    task.cancel_requested.store(true, .release);
    if (task.pool.queue.drop(task)) {
        markCancelled(task);
        task.pool.complete(task);
        return NativeResult.scalar(.{ .bool = true });
    }
    task.mutex.lock();
    defer task.mutex.unlock();
    return NativeResult.scalar(.{ .bool = task.state == .cancelled });
}

fn futureId(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const task = taskOf(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(task.id) });
}

fn taskCancelled(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const task = current_task orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = task.cancel_requested.load(.acquire) });
}

fn taskId(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const task = current_task orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = @intCast(task.id) });
}

fn taskWorker(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (current_worker < 0) return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = current_worker });
}

// ---------------------------------------------------------------------------
// lifetimes

fn cleanupPool(obj: *PhpObject) bool {
    const pool = obj.native.get(Pool, .pool) orelse return true;
    obj.native = .{};
    pool.destroy();
    return true;
}

fn cleanupFuture(obj: *PhpObject) bool {
    const task = taskOf(obj) orelse return true;
    obj.native = .{};
    task.future = null;
    task.release();
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled) continue;
        if (obj.native.kind == .future) _ = cleanupFuture(obj);
    }
    for (objects.items) |obj| {
        if (obj.pooled) continue;
        if (obj.native.kind == .pool) _ = cleanupPool(obj);
    }
}

// ---------------------------------------------------------------------------
// registration

fn method(a: std.mem.Allocator, def: *ClassDef, name: []const u8, arity: u8, is_static: bool) !void {
    try def.methods.put(a, name, .{ .name = name, .arity = arity, .is_static = is_static });
}

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    var pool_def = ClassDef{ .name = pool_class, .is_final = true, .native_cleanup = cleanupPool };
    try method(a, &pool_def, "__construct", 3, false);
    try method(a, &pool_def, "submit", 2, false);
    try method(a, &pool_def, "trySubmit", 2, false);
    try method(a, &pool_def, "collect", 1, false);
    try method(a, &pool_def, "readiness", 0, false);
    try method(a, &pool_def, "shutdown", 1, false);
    try method(a, &pool_def, "workers", 0, false);
    try vm.classes.put(a, pool_class, pool_def);
    try vm.native_fns.put(a, pool_class ++ "::__construct", poolConstruct);
    try vm.native_fns.put(a, pool_class ++ "::submit", poolSubmit);
    try vm.native_fns.put(a, pool_class ++ "::trySubmit", poolTrySubmit);
    try vm.native_fns.put(a, pool_class ++ "::collect", poolCollect);
    try vm.native_fns.put(a, pool_class ++ "::readiness", poolReadiness);
    try vm.native_fns.put(a, pool_class ++ "::shutdown", poolShutdown);
    try vm.native_fns.put(a, pool_class ++ "::workers", poolWorkers);

    var future_def = ClassDef{ .name = future_class, .is_final = true, .native_cleanup = cleanupFuture };
    try method(a, &future_def, "isDone", 0, false);
    try method(a, &future_def, "await", 1, false);
    try method(a, &future_def, "cancel", 0, false);
    try method(a, &future_def, "id", 0, false);
    try vm.classes.put(a, future_class, future_def);
    try vm.native_fns.put(a, future_class ++ "::isDone", futureIsDone);
    try vm.native_fns.put(a, future_class ++ "::await", futureAwait);
    try vm.native_fns.put(a, future_class ++ "::cancel", futureCancel);
    try vm.native_fns.put(a, future_class ++ "::id", futureId);

    var task_def = ClassDef{ .name = task_class, .is_final = true };
    try method(a, &task_def, "cancelled", 0, true);
    try method(a, &task_def, "id", 0, true);
    try method(a, &task_def, "worker", 0, true);
    try vm.classes.put(a, task_class, task_def);
    try vm.native_fns.put(a, task_class ++ "::cancelled", taskCancelled);
    try vm.native_fns.put(a, task_class ++ "::id", taskId);
    try vm.native_fns.put(a, task_class ++ "::worker", taskWorker);

    inline for (.{ pool_exception, task_exception, cancelled_exception, timeout_exception, transfer_exception }) |name| {
        try vm.classes.put(a, name, ClassDef{ .name = name, .parent = "Exception" });
    }
}
