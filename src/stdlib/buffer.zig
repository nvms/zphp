// a Zphp\Buffer is a window (offset, length) onto a region of bytes. slices
// are windows onto their parent's region, so they share its bytes. a region
// belongs to one vm at a time: a window that crosses to another thread moves
// the region's storage into the payload without copying it, and every window
// this vm still holds on that region is detached
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const workers = @import("workers.zig");
const filesystem = @import("filesystem.zig");

pub const buffer_class = "Zphp\\Buffer";
const transfer_exception = "Zphp\\TransferException";

// ---------------------------------------------------------------------------
// storage crosses threads, regions and windows stay in their vm

pub const Storage = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn create(allocator: std.mem.Allocator, len: usize) !*Storage {
        const s = try allocator.create(Storage);
        errdefer allocator.destroy(s);
        s.* = .{ .allocator = allocator, .bytes = try allocator.alloc(u8, len) };
        @memset(s.bytes, 0);
        return s;
    }

    pub fn free(s: *Storage) void {
        s.allocator.free(s.bytes);
        s.allocator.destroy(s);
    }
};

const Region = struct {
    allocator: std.mem.Allocator,
    storage: ?*Storage,
    refs: u32 = 1,

    fn create(allocator: std.mem.Allocator, storage: *Storage) !*Region {
        const r = try allocator.create(Region);
        r.* = .{ .allocator = allocator, .storage = storage };
        return r;
    }

    fn retain(r: *Region) void {
        r.refs += 1;
    }

    fn release(r: *Region) void {
        r.refs -= 1;
        if (r.refs > 0) return;
        if (r.storage) |s| s.free();
        r.allocator.destroy(r);
    }
};

const Window = struct {
    region: *Region,
    offset: usize,
    len: usize,

    fn bytes(w: Window) ?[]u8 {
        const s = w.region.storage orelse return null;
        return s.bytes[w.offset..][0..w.len];
    }
};

fn windowOf(obj: *PhpObject) ?Window {
    const region = obj.native.get(Region, .buffer) orelse return null;
    return .{ .region = region, .offset = obj.native.aux, .len = obj.native.extra };
}

// the object takes a reference to the region
fn bind(obj: *PhpObject, w: Window) void {
    w.region.retain();
    obj.native = .{ .kind = .buffer, .ptr = @intFromPtr(w.region), .aux = w.offset, .extra = w.len };
}

fn newRegion(ctx: *NativeContext, len: usize) RuntimeError!*Region {
    const storage = Storage.create(workers.transferAllocator(ctx.allocator), len) catch return error.OutOfMemory;
    errdefer storage.free();
    return Region.create(ctx.allocator, storage);
}

// the region's reference passes to the new object
fn wrap(ctx: *NativeContext, w: Window) RuntimeError!*PhpObject {
    errdefer w.region.release();
    const obj = try ctx.createObject(buffer_class);
    obj.native = .{ .kind = .buffer, .ptr = @intFromPtr(w.region), .aux = w.offset, .extra = w.len };
    return obj;
}

// ---------------------------------------------------------------------------
// transfer: workers.pack serializes under an Outgoing, which collects each
// region a window names and then moves its storage into the payload.
// workers.unpack unserializes under an Incoming, which rebuilds one region
// per moved storage and binds every window onto it

pub const Outgoing = struct {
    regions: std.AutoArrayHashMapUnmanaged(*Region, void) = .{},

    fn indexOf(self: *Outgoing, ctx: *NativeContext, region: *Region) RuntimeError!usize {
        const entry = try self.regions.getOrPut(ctx.allocator, region);
        if (!entry.found_existing) region.retain();
        return entry.index;
    }

    // after the bytes are final; nothing is detached if this fails
    pub fn detach(self: *Outgoing, allocator: std.mem.Allocator) ![]?*Storage {
        const moved = try allocator.alloc(?*Storage, self.regions.count());
        for (self.regions.keys(), moved) |r, *slot| {
            slot.* = r.storage;
            r.storage = null;
        }
        return moved;
    }

    pub fn deinit(self: *Outgoing, a: std.mem.Allocator) void {
        for (self.regions.keys()) |r| r.release();
        self.regions.deinit(a);
    }
};

pub const Incoming = struct {
    storages: []?*Storage,
    regions: []?*Region = &.{},

    fn region(self: *Incoming, ctx: *NativeContext, index: usize) RuntimeError!?*Region {
        if (index >= self.storages.len) return null;
        if (self.regions.len == 0) {
            self.regions = try ctx.allocator.alloc(?*Region, self.storages.len);
            @memset(self.regions, null);
        }
        if (self.regions[index]) |r| return r;
        const storage = self.storages[index] orelse return null;
        const r = try Region.create(ctx.allocator, storage);
        self.storages[index] = null;
        self.regions[index] = r;
        return r;
    }

    pub fn deinit(self: *Incoming, a: std.mem.Allocator) void {
        for (self.regions) |r| if (r) |region_| region_.release();
        a.free(self.regions);
    }
};

threadlocal var outgoing: ?*Outgoing = null;
threadlocal var incoming: ?*Incoming = null;

pub fn beginOutgoing(out: *Outgoing) ?*Outgoing {
    const prev = outgoing;
    outgoing = out;
    return prev;
}

pub fn endOutgoing(prev: ?*Outgoing) void {
    outgoing = prev;
}

pub fn beginIncoming(in: *Incoming) ?*Incoming {
    const prev = incoming;
    incoming = in;
    return prev;
}

pub fn endIncoming(prev: ?*Incoming) void {
    incoming = prev;
}

pub fn isDetached(obj: *PhpObject) bool {
    const w = windowOf(obj) orelse return false;
    return w.region.storage == null;
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
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class_name, msg);
    return error.RuntimeError;
}

fn thisWindow(ctx: *NativeContext) RuntimeError!Window {
    const obj = getThis(ctx) orelse return throwNamed(ctx, "Error", "the buffer is not initialized", .{});
    return windowOf(obj) orelse throwNamed(ctx, "Error", "the buffer is not initialized", .{});
}

fn thisBytes(ctx: *NativeContext) RuntimeError![]u8 {
    return (try thisWindow(ctx)).bytes() orelse throwNamed(ctx, transfer_exception, "the buffer was transferred to another thread", .{});
}

fn intArg(ctx: *NativeContext, args: []const Value, index: usize, comptime method: []const u8, comptime param: []const u8) RuntimeError!i64 {
    const v: Value = if (index < args.len) args[index] else .null;
    if (v == .int) return v.int;
    return throwNamed(ctx, "TypeError", buffer_class ++ "::" ++ method ++ "(): Argument #{d} (${s}) must be of type int, {s} given", .{ index + 1, param, v.typeName() });
}

fn lengthArg(ctx: *NativeContext, args: []const Value, index: usize, comptime method: []const u8) RuntimeError!usize {
    const n = try intArg(ctx, args, index, method, "length");
    if (n < 0) return throwNamed(ctx, "ValueError", buffer_class ++ "::" ++ method ++ "(): Argument #{d} ($length) must be greater than or equal to 0", .{index + 1});
    return @intCast(n);
}

// the width bytes at offset, which must lie inside the window
fn span(ctx: *NativeContext, bytes: []u8, offset: i64, width: usize) RuntimeError![]u8 {
    if (offset < 0 or @as(u64, @intCast(offset)) > bytes.len or width > bytes.len - @as(usize, @intCast(offset))) {
        return throwNamed(ctx, "ValueError", "offset {d} with length {d} is outside a {d}-byte buffer", .{ offset, width, bytes.len });
    }
    return bytes[@intCast(offset)..][0..width];
}

fn construct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const len = try lengthArg(ctx, args, 0, "__construct");
    if (obj.native.kind != .none) return throwNamed(ctx, "Error", "the buffer is already initialized", .{});
    const region = try newRegion(ctx, len);
    obj.native = .{ .kind = .buffer, .ptr = @intFromPtr(region), .extra = len };
    return NativeResult.scalar(.null);
}

fn fromString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return throwNamed(ctx, "TypeError", buffer_class ++ "::fromString(): Argument #1 ($bytes) must be of type string, {s} given", .{Value.typeName(if (args.len > 0) args[0] else .null)});
    const src = args[0].string.bytes();
    const region = try newRegion(ctx, src.len);
    @memcpy(region.storage.?.bytes, src);
    return NativeResult.borrowed(.{ .object = try wrap(ctx, .{ .region = region, .offset = 0, .len = src.len }) });
}

fn length(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .int = @intCast((try thisBytes(ctx)).len) });
}

fn slice(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const w = try thisWindow(ctx);
    const bytes = try thisBytes(ctx);
    const offset = try intArg(ctx, args, 0, "slice", "offset");
    _ = try span(ctx, bytes, offset, 0);
    const start: usize = @intCast(offset);
    const len = if (args.len < 2 or args[1] == .null) bytes.len - start else try lengthArg(ctx, args, 1, "slice");
    _ = try span(ctx, bytes, offset, len);
    w.region.retain();
    return NativeResult.borrowed(.{ .object = try wrap(ctx, .{ .region = w.region, .offset = w.offset + start, .len = len }) });
}

fn toString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.copyString(ctx.allocator, try thisBytes(ctx));
}

fn write(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const bytes = try thisBytes(ctx);
    const offset = try intArg(ctx, args, 0, "write", "offset");
    const src: []const u8 = switch (if (args.len > 1) args[1] else .null) {
        .string => |s| s.bytes(),
        .object => |o| if (windowOf(o)) |w| w.bytes() orelse return throwNamed(ctx, transfer_exception, "the source buffer was transferred to another thread", .{}) else null,
        else => null,
    } orelse return throwNamed(ctx, "TypeError", buffer_class ++ "::write(): Argument #2 ($data) must be of type " ++ buffer_class ++ "|string, {s} given", .{Value.typeName(if (args.len > 1) args[1] else .null)});
    const dest = try span(ctx, bytes, offset, src.len);
    if (@intFromPtr(dest.ptr) <= @intFromPtr(src.ptr)) std.mem.copyForwards(u8, dest, src) else std.mem.copyBackwards(u8, dest, src);
    return NativeResult.scalar(.null);
}

fn streamArg(ctx: *NativeContext, args: []const Value, comptime method: []const u8) RuntimeError!*PhpObject {
    return filesystem.streamArg(ctx, args, .{ .func = buffer_class ++ "::" ++ method });
}

fn readFrom(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const bytes = try thisBytes(ctx);
    const stream = try streamArg(ctx, args, "readFrom");
    const n = (try filesystem.streamReadInto(ctx, stream, bytes)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(n) });
}

fn writeTo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const bytes = try thisBytes(ctx);
    const stream = try streamArg(ctx, args, "writeTo");
    const n = (try filesystem.streamWrite(ctx, stream, bytes)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(n) });
}

fn detached(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const w = try thisWindow(ctx);
    return NativeResult.scalar(.{ .bool = w.region.storage == null });
}

// ---------------------------------------------------------------------------
// fixed-width numbers

fn Bits(comptime T: type) type {
    return @Int(.unsigned, @bitSizeOf(T));
}

fn reader(comptime T: type, comptime endian: std.builtin.Endian, comptime method: []const u8) vm_mod.NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const bytes = try thisBytes(ctx);
            const at = try span(ctx, bytes, try intArg(ctx, args, 0, method, "offset"), @sizeOf(T));
            const raw: T = @bitCast(std.mem.readInt(Bits(T), at[0..@sizeOf(T)], endian));
            if (@typeInfo(T) == .float) return NativeResult.scalar(.{ .float = @floatCast(raw) });
            return NativeResult.scalar(.{ .int = @intCast(raw) });
        }
    }.call;
}

fn writer(comptime T: type, comptime endian: std.builtin.Endian, comptime method: []const u8) vm_mod.NativeFn {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const bytes = try thisBytes(ctx);
            const at = try span(ctx, bytes, try intArg(ctx, args, 0, method, "offset"), @sizeOf(T));
            std.mem.writeInt(Bits(T), at[0..@sizeOf(T)], @bitCast(try number(ctx, args)), endian);
            return NativeResult.scalar(.null);
        }

        fn number(ctx: *NativeContext, args: []const Value) RuntimeError!T {
            const v: Value = if (args.len > 1) args[1] else .null;
            if (@typeInfo(T) == .float) return switch (v) {
                .int => |i| @floatFromInt(i),
                .float => |f| @floatCast(f),
                else => throwNamed(ctx, "TypeError", buffer_class ++ "::" ++ method ++ "(): Argument #2 ($value) must be of type float, {s} given", .{v.typeName()}),
            };
            if (v != .int) return throwNamed(ctx, "TypeError", buffer_class ++ "::" ++ method ++ "(): Argument #2 ($value) must be of type int, {s} given", .{v.typeName()});
            return std.math.cast(T, v.int) orelse throwNamed(ctx, "ValueError", buffer_class ++ "::" ++ method ++ "(): Argument #2 ($value) must be between {d} and {d}", .{ std.math.minInt(T), std.math.maxInt(T) });
        }
    }.call;
}

const Numeric = struct { name: []const u8, T: type, endian: std.builtin.Endian };

const numerics = [_]Numeric{
    .{ .name = "Int8", .T = i8, .endian = .little },
    .{ .name = "UInt8", .T = u8, .endian = .little },
    .{ .name = "Int16LE", .T = i16, .endian = .little },
    .{ .name = "Int16BE", .T = i16, .endian = .big },
    .{ .name = "UInt16LE", .T = u16, .endian = .little },
    .{ .name = "UInt16BE", .T = u16, .endian = .big },
    .{ .name = "Int32LE", .T = i32, .endian = .little },
    .{ .name = "Int32BE", .T = i32, .endian = .big },
    .{ .name = "UInt32LE", .T = u32, .endian = .little },
    .{ .name = "UInt32BE", .T = u32, .endian = .big },
    .{ .name = "Int64LE", .T = i64, .endian = .little },
    .{ .name = "Int64BE", .T = i64, .endian = .big },
    .{ .name = "Float32LE", .T = f32, .endian = .little },
    .{ .name = "Float32BE", .T = f32, .endian = .big },
    .{ .name = "Float64LE", .T = f64, .endian = .little },
    .{ .name = "Float64BE", .T = f64, .endian = .big },
};

// ---------------------------------------------------------------------------
// serialization: plain serialize() copies the bytes; inside a transfer the
// window names its region in the payload instead

fn stringKey(comptime k: []const u8) value_mod.PhpArray.Key {
    return .{ .string = Value.String.borrowed(k) };
}

fn serializeBuffer(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const w = try thisWindow(ctx);
    const bytes = try thisBytes(ctx);
    const arr = try ctx.createArray();
    if (outgoing) |out| {
        try arr.set(ctx.allocator, stringKey("region"), .{ .int = @intCast(try out.indexOf(ctx, w.region)) });
        try arr.set(ctx.allocator, stringKey("offset"), .{ .int = @intCast(w.offset) });
        try arr.set(ctx.allocator, stringKey("length"), .{ .int = @intCast(w.len) });
        return NativeResult.borrowed(.{ .array = arr });
    }
    const copy = try Value.String.create(ctx.allocator, bytes);
    defer copy.release();
    try arr.set(ctx.allocator, stringKey("bytes"), .{ .string = copy });
    return NativeResult.borrowed(.{ .array = arr });
}

fn field(data: *value_mod.PhpArray, comptime k: []const u8) Value {
    return data.get(stringKey(k));
}

fn nonNegative(v: Value) ?usize {
    return if (v == .int and v.int >= 0) @intCast(v.int) else null;
}

fn unserializeBuffer(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (obj.native.kind != .none) return NativeResult.scalar(.null);
    const data = if (args.len > 0 and args[0] == .array) args[0].array else return throwNamed(ctx, transfer_exception, "invalid buffer data", .{});
    const bytes = field(data, "bytes");
    if (bytes == .string) {
        const region = try newRegion(ctx, bytes.string.bytes().len);
        @memcpy(region.storage.?.bytes, bytes.string.bytes());
        obj.native = .{ .kind = .buffer, .ptr = @intFromPtr(region), .extra = region.storage.?.bytes.len };
        return NativeResult.scalar(.null);
    }
    const index = nonNegative(field(data, "region")) orelse return throwNamed(ctx, transfer_exception, "invalid buffer data", .{});
    const in = incoming orelse return throwNamed(ctx, transfer_exception, "a transferred buffer can only be received by the thread it was sent to", .{});
    const region = (try in.region(ctx, index)) orelse return throwNamed(ctx, transfer_exception, "invalid buffer data", .{});
    const offset = nonNegative(field(data, "offset")) orelse return throwNamed(ctx, transfer_exception, "invalid buffer data", .{});
    const len = nonNegative(field(data, "length")) orelse return throwNamed(ctx, transfer_exception, "invalid buffer data", .{});
    const total = region.storage.?.bytes.len;
    if (offset > total or len > total - offset) return throwNamed(ctx, transfer_exception, "invalid buffer data", .{});
    bind(obj, .{ .region = region, .offset = offset, .len = len });
    return NativeResult.scalar(.null);
}

// ---------------------------------------------------------------------------
// lifetimes

fn cleanupBuffer(obj: *PhpObject) bool {
    const region = obj.native.get(Region, .buffer) orelse return true;
    obj.native = .{};
    region.release();
    return true;
}

// a clone owns a copy of the window's bytes; a detached window clones detached
fn cloneBuffer(vm: *VM, src: *PhpObject, copy: *PhpObject) bool {
    const w = windowOf(src) orelse return false;
    const bytes = w.bytes() orelse {
        bind(copy, w);
        return true;
    };
    const storage = Storage.create(workers.transferAllocator(vm.allocator), bytes.len) catch return false;
    @memcpy(storage.bytes, bytes);
    const region = Region.create(vm.allocator, storage) catch {
        storage.free();
        return false;
    };
    copy.native = .{ .kind = .buffer, .ptr = @intFromPtr(region), .extra = bytes.len };
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled) continue;
        if (obj.native.kind == .buffer) _ = cleanupBuffer(obj);
    }
}

// ---------------------------------------------------------------------------
// registration

const Method = struct { name: []const u8, arity: u8, native: vm_mod.NativeFn, is_static: bool = false };

const methods = [_]Method{
    .{ .name = "__construct", .arity = 1, .native = construct },
    .{ .name = "fromString", .arity = 1, .native = fromString, .is_static = true },
    .{ .name = "length", .arity = 0, .native = length },
    .{ .name = "slice", .arity = 2, .native = slice },
    .{ .name = "toString", .arity = 0, .native = toString },
    .{ .name = "write", .arity = 2, .native = write },
    .{ .name = "readFrom", .arity = 1, .native = readFrom },
    .{ .name = "writeTo", .arity = 1, .native = writeTo },
    .{ .name = "isDetached", .arity = 0, .native = detached },
    .{ .name = "__serialize", .arity = 0, .native = serializeBuffer },
    .{ .name = "__unserialize", .arity = 1, .native = unserializeBuffer },
};

fn put(vm: *VM, a: std.mem.Allocator, def: *ClassDef, comptime m: Method) !void {
    try def.methods.put(a, m.name, .{ .name = m.name, .arity = m.arity, .is_static = m.is_static });
    try vm.native_fns.put(a, buffer_class ++ "::" ++ m.name, m.native);
}

pub fn register(vm: *VM, a: std.mem.Allocator) !void {
    var def = ClassDef{ .name = buffer_class, .is_final = true, .native_cleanup = cleanupBuffer, .native_clone = cloneBuffer };
    inline for (methods) |m| try put(vm, a, &def, m);
    inline for (numerics) |n| {
        try put(vm, a, &def, .{ .name = "read" ++ n.name, .arity = 1, .native = reader(n.T, n.endian, "read" ++ n.name) });
        try put(vm, a, &def, .{ .name = "write" ++ n.name, .arity = 2, .native = writer(n.T, n.endian, "write" ++ n.name) });
    }
    try vm.classes.put(a, buffer_class, def);
}
