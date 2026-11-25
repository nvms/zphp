// php 8.6's Time\Duration (ext/date/time_duration.c over timelib's
// duration.c): an immutable span of up to 9_223_372_035 seconds, kept as
// unsigned seconds, nanoseconds below a second and a sign. its public
// readonly properties are the whole state, so every method reads them back.
// php keeps the last non-negative duration a from*() factory made and hands
// the same object back for the same value (DATEG(duration_cache)); the vm's
// duration_cache does that for the request
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Args = @import("string_ports.zig").Args;
const iso = @import("date_iso_interval.zig");
const phpTypeName = @import("types.zig").phpTypeName;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const class_name = "Time\\Duration";
pub const exception_class = "Time\\TimeException";

const nanos_per_sec: u64 = 1_000_000_000;
// timelib's MAX_DURATION_SECONDS: the most seconds that still fit the whole
// duration in one int64 of nanoseconds
const max_seconds: u64 = 9_223_372_035;

pub const Span = struct {
    seconds: u64 = 0,
    nanoseconds: u32 = 0,
    negative: bool = false,
};

// timelib's error codes, as throw_timelib_error maps them
const Failure = error{ seconds_out_of_range, nanoseconds_out_of_range, division_by_zero, overflow, iso_only_period, iso_missing_period, iso_days_found, iso_parse };

pub fn register(vm: *VM, a: Allocator) !void {
    try vm.classes.put(a, exception_class, .{ .name = exception_class, .parent = "Exception" });

    var def = ClassDef{ .name = class_name, .is_final = true, .is_readonly = true, .native_binop = durationBinop };
    try def.properties.append(a, .{ .name = "seconds", .default = .undef, .is_readonly = true, .type_str = "int" });
    try def.properties.append(a, .{ .name = "nanoseconds", .default = .undef, .is_readonly = true, .type_str = "int" });
    try def.properties.append(a, .{ .name = "negative", .default = .undef, .is_readonly = true, .type_str = "bool" });
    def.slot_layout = try vm.buildSlotLayout(&def);
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0, .visibility = .private });
    try def.methods.put(a, "__unserialize", .{ .name = "__unserialize", .arity = 1 });
    const statics = .{
        .{ "fromSeconds", 2 },      .{ "fromNanoseconds", 1 }, .{ "fromMicroseconds", 1 },          .{ "fromMilliseconds", 1 },
        .{ "fromMinutes", 1 },      .{ "fromHours", 1 },       .{ "fromIso8601DurationString", 1 }, .{ "compare", 2 },
    };
    inline for (statics) |m| try def.methods.put(a, m[0], .{ .name = m[0], .arity = m[1], .is_static = true });
    const methods = .{ .{ "negate", 0 }, .{ "absolute", 0 }, .{ "add", 1 }, .{ "sub", 1 }, .{ "multiplyBy", 1 }, .{ "divideBy", 1 } };
    inline for (methods) |m| try def.methods.put(a, m[0], .{ .name = m[0], .arity = m[1] });
    try vm.classes.put(a, class_name, def);

    const natives = .{
        .{ "__construct", construct },                                 .{ "__unserialize", unserialize },
        .{ "fromSeconds", fromSeconds },                               .{ "fromNanoseconds", fromNanoseconds },
        .{ "fromMicroseconds", fromMicroseconds },                     .{ "fromMilliseconds", fromMilliseconds },
        .{ "fromMinutes", fromMinutes },                               .{ "fromHours", fromHours },
        .{ "fromIso8601DurationString", fromIso8601DurationString }, .{ "negate", negate },
        .{ "absolute", absolute },                                     .{ "add", add },
        .{ "sub", sub },                                               .{ "multiplyBy", multiplyBy },
        .{ "divideBy", divideBy },                                     .{ "compare", compare },
    };
    inline for (natives) |n| try vm.native_fns.put(a, class_name ++ "::" ++ n[0], n[1]);
}

// ---- the duration a Time\Duration holds ------------------------------------

pub fn isDuration(v: Value) bool {
    return v == .object and std.mem.eql(u8, v.object.class_name, class_name);
}

// the span an object's properties hold; an uninitialized one is zero, as
// php's create_object starts it
pub fn spanOf(obj: *PhpObject) Span {
    const s = obj.get("seconds");
    const n = obj.get("nanoseconds");
    const neg = obj.get("negative");
    return .{
        .seconds = if (s == .int and s.int >= 0) @intCast(s.int) else 0,
        .nanoseconds = if (n == .int and n.int >= 0 and n.int < nanos_per_sec) @intCast(n.int) else 0,
        .negative = neg == .bool and neg.bool,
    };
}

// timelib_duration_ctor_static: a zero duration is never negative
fn construct_span(seconds: u64, nanoseconds: u64, negative: bool) Failure!Span {
    if (seconds > max_seconds) return error.seconds_out_of_range;
    if (nanoseconds >= nanos_per_sec) return error.nanoseconds_out_of_range;
    return .{ .seconds = seconds, .nanoseconds = @intCast(nanoseconds), .negative = negative and (seconds != 0 or nanoseconds != 0) };
}

fn absCompare(a: Span, b: Span) i64 {
    if (a.seconds != b.seconds) return if (a.seconds < b.seconds) -1 else 1;
    if (a.nanoseconds != b.nanoseconds) return if (a.nanoseconds < b.nanoseconds) -1 else 1;
    return 0;
}

fn spanCompare(a: Span, b: Span) i64 {
    if (a.negative and !b.negative) return -1;
    if (!a.negative and b.negative) return 1;
    if (a.negative) return absCompare(b, a);
    return absCompare(a, b);
}

fn addAbs(a: Span, b: Span) Failure!Span {
    var seconds = a.seconds + b.seconds;
    var nanoseconds: u64 = @as(u64, a.nanoseconds) + b.nanoseconds;
    if (nanoseconds >= nanos_per_sec) {
        seconds += 1;
        nanoseconds -= nanos_per_sec;
    }
    return construct_span(seconds, nanoseconds, a.negative);
}

// a is the larger in absolute value
fn subAbs(a: Span, b: Span) Failure!Span {
    var seconds = a.seconds - b.seconds;
    var nanoseconds: i64 = @as(i64, a.nanoseconds) - @as(i64, b.nanoseconds);
    if (nanoseconds < 0) {
        seconds -%= 1;
        nanoseconds += @intCast(nanos_per_sec);
    }
    return construct_span(seconds, @intCast(nanoseconds), a.negative);
}

fn spanAdd(a: Span, b: Span) Failure!Span {
    if (a.negative == b.negative) return addAbs(a, b);
    return switch (absCompare(a, b)) {
        -1 => subAbs(b, a),
        0 => .{},
        else => subAbs(a, b),
    };
}

fn spanSub(a: Span, b: Span) Failure!Span {
    if (a.negative != b.negative) return addAbs(a, b);
    return switch (absCompare(a, b)) {
        -1 => blk: {
            const t = try subAbs(b, a);
            break :blk construct_span(t.seconds, t.nanoseconds, !t.negative);
        },
        0 => .{},
        else => subAbs(a, b),
    };
}

fn spanMul(a: Span, factor: u64) Failure!Span {
    if (factor == 0) return .{};
    if (a.seconds > std.math.maxInt(u64) / factor) return error.overflow;
    var seconds = a.seconds * factor;
    var extra = @as(u64, a.nanoseconds) * (factor / nanos_per_sec);
    var nanoseconds = @as(u64, a.nanoseconds) * (factor % nanos_per_sec);
    extra += nanoseconds / nanos_per_sec;
    nanoseconds %= nanos_per_sec;
    if (std.math.maxInt(u64) - extra < seconds) return error.overflow;
    seconds += extra;
    return construct_span(seconds, nanoseconds, a.negative);
}

fn spanDiv(a: Span, divisor: u64) Failure!Span {
    if (divisor < 1) return error.division_by_zero;
    const seconds = a.seconds / divisor;
    const nanoseconds = (@as(u64, a.nanoseconds) + (a.seconds % divisor) * nanos_per_sec) / divisor;
    return construct_span(seconds, nanoseconds, a.negative);
}

// ---- errors ------------------------------------------------------------------

fn throwOutOfRange(ctx: *NativeContext) RuntimeError {
    try ctx.vm.setPendingException(exception_class, "The maximum representable range is 9_223_372_035 seconds (roughly 292 years)");
    return error.RuntimeError;
}

fn throwFailure(ctx: *NativeContext, failure: Failure) RuntimeError {
    const msg: []const u8 = switch (failure) {
        error.seconds_out_of_range => return throwOutOfRange(ctx),
        error.division_by_zero => {
            try ctx.vm.setPendingException("DivisionByZeroError", "Division by zero");
            return error.RuntimeError;
        },
        error.iso_only_period => "The ISO 8601 duration string may only contain the period (P) aspect",
        error.iso_missing_period => "The ISO 8601 duration string is missing the period (P) aspect",
        error.iso_days_found => "The ISO 8601 duration string may only contain the time (T) aspect",
        error.iso_parse => "The ISO 8601 duration string could not be parsed",
        // the codes php never expects to see
        error.nanoseconds_out_of_range => "Failed to create a Time\\Duration: Nanoseconds value out of range",
        error.overflow => "Failed to create a Time\\Duration: Integer Overflow",
    };
    try ctx.vm.setPendingException(exception_class, msg);
    return error.RuntimeError;
}

// ---- making objects ----------------------------------------------------------

fn setProps(ctx: *NativeContext, obj: *PhpObject, span: Span) RuntimeError!void {
    try obj.set(ctx.allocator, "seconds", .{ .int = @intCast(span.seconds) });
    try obj.set(ctx.allocator, "nanoseconds", .{ .int = span.nanoseconds });
    try obj.set(ctx.allocator, "negative", .{ .bool = span.negative });
}

// create_duration_shell + sync_properties
// create_duration_shell + sync_properties. php makes the object before it
// knows the result, so a failed one still takes a handle until the call ends
fn makeObject(ctx: *NativeContext, result: Failure!Span) RuntimeError!NativeResult {
    const obj = try ctx.createObject(class_name);
    const span = result catch |f| return discard(ctx, obj, f);
    if (span.seconds > max_seconds) return discard(ctx, obj, error.seconds_out_of_range);
    try setProps(ctx, obj, span);
    return NativeResult.borrowed(.{ .object = obj });
}

fn discard(ctx: *NativeContext, obj: *PhpObject, failure: Failure) RuntimeError {
    obj.retain();
    defer ctx.vm.releaseValue(.{ .object = obj });
    return throwFailure(ctx, failure);
}

// create_duration: a non-negative duration, the cached object when it has
// the same value, and the cached one from now on otherwise
fn makeCached(ctx: *NativeContext, seconds: u64, nanoseconds: u64) RuntimeError!NativeResult {
    const vm = ctx.vm;
    if (vm.duration_cache) |cached| {
        const s = spanOf(cached);
        if (s.seconds == seconds and s.nanoseconds == nanoseconds) return NativeResult.borrowed(.{ .object = cached });
    }
    const result = try makeObject(ctx, construct_span(seconds, nanoseconds, false));
    const obj = result.value.object;
    obj.retain();
    const old_cache = vm.duration_cache;
    vm.duration_cache = obj;
    if (old_cache) |old| {
        vm.releaseValue(.{ .object = old });
        // php frees the one it drops at once, so its handle is free for the
        // next object
        if (old.refcount == 0 and vm.hasPendingReleases()) vm.drainPendingDestruct();
    }
    return result;
}

fn thisDuration(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    return if (isDuration(v)) v.object else null;
}

// Z_PARAM_ULONG: an int that is not negative
fn ulong(a: Args, index: usize, comptime name: []const u8) RuntimeError!u64 {
    const v = try a.long(index, name);
    if (v < 0) return a.valueError(index, name, "must be greater than or equal to 0");
    return @intCast(v);
}

// ---- methods -------------------------------------------------------------------

fn construct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    try ctx.vm.setPendingException("Error", "Cannot directly construct Time\\Duration, use Time\\Duration::from*() methods instead");
    return error.RuntimeError;
}

fn fromSeconds(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, class_name ++ "::fromSeconds", args);
    const seconds = try ulong(a, 0, "seconds");
    const nanoseconds: u64 = if (args.len > 1) try ulong(a, 1, "nanoseconds") else 0;
    if (nanoseconds >= nanos_per_sec) return a.valueError(1, "nanoseconds", "must be less than 1_000_000_000");
    return makeCached(ctx, seconds, nanoseconds);
}

fn fromNanoseconds(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const n = try ulong(Args.init(ctx, class_name ++ "::fromNanoseconds", args), 0, "nanoseconds");
    return makeCached(ctx, n / nanos_per_sec, n % nanos_per_sec);
}

fn fromMicroseconds(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const n = try ulong(Args.init(ctx, class_name ++ "::fromMicroseconds", args), 0, "microseconds");
    return makeCached(ctx, n / 1_000_000, (n % 1_000_000) * 1000);
}

fn fromMilliseconds(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const n = try ulong(Args.init(ctx, class_name ++ "::fromMilliseconds", args), 0, "milliseconds");
    return makeCached(ctx, n / 1000, (n % 1000) * 1_000_000);
}

fn fromMinutes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const n = try ulong(Args.init(ctx, class_name ++ "::fromMinutes", args), 0, "minutes");
    if (n > std.math.maxInt(u64) / 60) return throwOutOfRange(ctx);
    return makeCached(ctx, n * 60, 0);
}

fn fromHours(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const n = try ulong(Args.init(ctx, class_name ++ "::fromHours", args), 0, "hours");
    if (n > std.math.maxInt(u64) / 3600) return throwOutOfRange(ctx);
    return makeCached(ctx, n * 3600, 0);
}

// timelib_duration_create_from_iso8601string: a period of hours, minutes
// and seconds only, through the parser DatePeriod uses
fn fromIso8601DurationString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const spec = try Args.init(ctx, class_name ++ "::fromIso8601DurationString", args).str(0, "specification");
    if (std.mem.indexOfScalar(u8, spec, 0) != null) return throwFailure(ctx, error.iso_parse);
    const parsed = iso.parse(spec);
    if (parsed.errors > 0) return throwFailure(ctx, error.iso_parse);
    const p = parsed.period orelse return throwFailure(ctx, error.iso_missing_period);
    if (parsed.begin != null or parsed.end != null or parsed.has_recurrences) return throwFailure(ctx, error.iso_only_period);
    if (p.y > 0 or p.m > 0 or p.d > 0) return throwFailure(ctx, error.iso_days_found);
    const total: i64 = p.h * 3600 + p.i * 60 + p.s;
    return makeObject(ctx, construct_span(@bitCast(total), 0, false));
}

fn negate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisDuration(ctx) orelse return NativeResult.scalar(.null);
    const s = spanOf(this);
    return makeObject(ctx, construct_span(s.seconds, s.nanoseconds, !s.negative));
}

fn absolute(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = thisDuration(ctx) orelse return NativeResult.scalar(.null);
    const s = spanOf(this);
    if (!s.negative) return NativeResult.borrowed(.{ .object = this });
    return makeCached(ctx, s.seconds, s.nanoseconds);
}

fn operand(ctx: *NativeContext, args: []const Value, comptime method: []const u8, index: usize, comptime name: []const u8) RuntimeError!Span {
    return spanOf(try Args.init(ctx, class_name ++ "::" ++ method, args).object(index, name, class_name));
}

fn add(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisDuration(ctx) orelse return NativeResult.scalar(.null);
    const other = try operand(ctx, args, "add", 0, "duration");
    return makeObject(ctx, spanAdd(spanOf(this), other));
}

fn sub(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisDuration(ctx) orelse return NativeResult.scalar(.null);
    const other = try operand(ctx, args, "sub", 0, "duration");
    return makeObject(ctx, spanSub(spanOf(this), other));
}

fn multiplyBy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisDuration(ctx) orelse return NativeResult.scalar(.null);
    const factor = try ulong(Args.init(ctx, class_name ++ "::multiplyBy", args), 0, "factor");
    return makeObject(ctx, spanMul(spanOf(this), factor));
}

fn divideBy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisDuration(ctx) orelse return NativeResult.scalar(.null);
    const divisor = try ulong(Args.init(ctx, class_name ++ "::divideBy", args), 0, "divisor");
    return makeObject(ctx, spanDiv(spanOf(this), divisor));
}

fn compare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = try operand(ctx, args, "compare", 0, "a");
    const b = try operand(ctx, args, "compare", 1, "b");
    return NativeResult.scalar(.{ .int = spanCompare(a, b) });
}

// php's compare handler for two durations; every other pairing takes the
// standard object comparison
fn durationBinop(_: *NativeContext, op: vm_mod.NativeBinop, a: Value, b: Value) RuntimeError!?Value {
    if (op != .compare or !isDuration(a) or !isDuration(b)) return null;
    if (a.object == b.object) return .{ .int = 0 };
    return .{ .int = spanCompare(spanOf(a.object), spanOf(b.object)) };
}

// ---- __unserialize -------------------------------------------------------------

const prop_names = [_][]const u8{ "seconds", "nanoseconds", "negative" };

fn propIndex(name: []const u8) ?usize {
    for (prop_names, 0..) |p, i| if (std.mem.eql(u8, p, name)) return i;
    return null;
}

// "\0Class\0name" and "\0*\0name" name the property after the last nul
fn unmangled(key: []const u8) []const u8 {
    if (key.len == 0 or key[0] != 0) return key;
    const last = std.mem.lastIndexOfScalar(u8, key, 0) orelse return key;
    return key[last + 1 ..];
}

fn throwPlain(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

// object_properties_load into the three typed readonly properties, as
// strict as php's: a reference, a set property, a wrong type or another
// key each stop it with php's error
fn loadProperties(ctx: *NativeContext, obj: *PhpObject, data: *value_mod.PhpArray) RuntimeError!void {
    for (data.entries.items) |entry| {
        const name = switch (entry.key) {
            .int => |i| return throwPlain(ctx, "Error", "Cannot create dynamic property " ++ class_name ++ "::${d}", .{i}),
            .string => |s| unmangled(s.bytes()),
        };
        const index = propIndex(name) orelse return throwPlain(ctx, "Error", "Cannot create dynamic property " ++ class_name ++ "::${s}", .{name});
        if (entry.ref != null) return throwPlain(ctx, "Error", "Cannot indirectly modify readonly property " ++ class_name ++ "::${s}", .{name});
        if (obj.rawForScope(name, null) != .undef) return throwPlain(ctx, "Error", "Cannot modify readonly property " ++ class_name ++ "::${s}", .{name});
        const v = entry.value;
        const ok = if (index == 2) v == .bool else v == .int;
        if (!ok) return throwPlain(ctx, "TypeError", "Cannot assign {s} to property " ++ class_name ++ "::${s} of type {s}", .{ phpTypeName(v), name, if (index == 2) "bool" else "int" });
        try obj.set(ctx.allocator, name, v);
    }
}

fn unserialize(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisDuration(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .array) return Args.init(ctx, class_name ++ "::__unserialize", args).typeError(0, "data", "array");
    loadProperties(ctx, this, args[0].array) catch |err| {
        if (err != error.RuntimeError) return err;
        return invalidData(ctx);
    };
    const s = this.get("seconds");
    const n = this.get("nanoseconds");
    const neg = this.get("negative");
    if (s != .int or n != .int or neg != .bool) return invalidData(ctx);
    if (s.int < 0 or n.int < 0 or n.int >= nanos_per_sec) return invalidData(ctx);
    const span = construct_span(@intCast(s.int), @intCast(n.int), neg.bool) catch |f| {
        throwFailure(ctx, f) catch {};
        return invalidData(ctx);
    };
    if (span.negative != neg.bool) return invalidData(ctx);
    return NativeResult.scalar(.null);
}

// the exception every failed restore ends in; one already thrown becomes
// its previous
fn invalidData(ctx: *NativeContext) RuntimeError {
    const cause = ctx.vm.takePending();
    defer if (cause) |c| ctx.vm.stackRelease(c);
    try ctx.vm.setPendingException("Exception", "Invalid serialization data for " ++ class_name ++ " object");
    if (cause) |c| if (c == .object) if (ctx.vm.pending_exception) |exc| if (exc == .object) {
        _ = try ctx.vm.chainPrevious(exc.object, c.object);
    };
    return error.RuntimeError;
}

test "duration arithmetic follows timelib" {
    const one: Span = .{ .seconds = 1 };
    const half: Span = .{ .nanoseconds = 500_000_000 };
    const r = try spanSub(half, one);
    try std.testing.expect(r.negative and r.seconds == 0 and r.nanoseconds == 500_000_000);
    try std.testing.expectError(error.overflow, spanMul(.{ .seconds = max_seconds, .nanoseconds = 999_999_999 }, std.math.maxInt(i64)));
    const d = try spanDiv(.{ .seconds = 2_147_483_647, .nanoseconds = 999_999_999 }, 999_999_999);
    try std.testing.expect(d.seconds == 2 and d.nanoseconds == 147_483_650);
    try std.testing.expectEqual(@as(i64, -1), spanCompare(.{ .seconds = 2, .negative = true }, .{ .seconds = 1, .negative = true }));
}
