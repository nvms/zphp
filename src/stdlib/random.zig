const std = @import("std");
const platform = @import("../platform.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Mt19937 = @import("mt19937.zig").Mt19937;
const Xoshiro256ss = @import("xoshiro256ss.zig").Xoshiro256ss;
const PcgOneseq128 = @import("pcg_oneseq_128.zig").PcgOneseq128;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    // PHP 8.3+ Random\Engine and Random\CryptoSafeEngine interfaces.
    // engines implement Engine; the Secure engine additionally implements
    // CryptoSafeEngine. registering the interface objects so userland code
    // can check `instanceof Random\Engine`
    var engine_iface = vm_mod.InterfaceDef{ .name = "Random\\Engine" };
    try engine_iface.methods.append(a, "generate");
    try vm.interfaces.put(a, "Random\\Engine", engine_iface);

    var crypto_engine_iface = vm_mod.InterfaceDef{ .name = "Random\\CryptoSafeEngine" };
    try crypto_engine_iface.parents.append(a, "Random\\Engine");
    try crypto_engine_iface.methods.append(a, "generate");
    try vm.interfaces.put(a, "Random\\CryptoSafeEngine", crypto_engine_iface);

    var rndmizer = ClassDef{ .name = "Random\\Randomizer", .is_final = true };
    try rndmizer.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try rndmizer.methods.put(a, "getBytes", .{ .name = "getBytes", .arity = 1 });
    try rndmizer.methods.put(a, "getInt", .{ .name = "getInt", .arity = 2 });
    try rndmizer.methods.put(a, "nextInt", .{ .name = "nextInt", .arity = 0 });
    try rndmizer.methods.put(a, "getFloat", .{ .name = "getFloat", .arity = 3 });
    try rndmizer.methods.put(a, "nextFloat", .{ .name = "nextFloat", .arity = 0 });
    try rndmizer.methods.put(a, "shuffleArray", .{ .name = "shuffleArray", .arity = 1 });
    try rndmizer.methods.put(a, "shuffleBytes", .{ .name = "shuffleBytes", .arity = 1 });
    try rndmizer.methods.put(a, "pickArrayKeys", .{ .name = "pickArrayKeys", .arity = 2 });
    try vm.classes.put(a, "Random\\Randomizer", rndmizer);

    try vm.native_fns.put(a, "Random\\Randomizer::__construct", rzConstruct);
    try vm.native_fns.put(a, "Random\\Randomizer::getBytes", rzGetBytes);
    try vm.native_fns.put(a, "Random\\Randomizer::getInt", rzGetInt);
    try vm.native_fns.put(a, "Random\\Randomizer::nextInt", rzNextInt);
    try vm.native_fns.put(a, "Random\\Randomizer::getFloat", rzGetFloat);
    try vm.native_fns.put(a, "Random\\Randomizer::nextFloat", rzNextFloat);
    try vm.native_fns.put(a, "Random\\Randomizer::shuffleArray", rzShuffleArray);
    try vm.native_fns.put(a, "Random\\Randomizer::shuffleBytes", rzShuffleBytes);
    try vm.native_fns.put(a, "Random\\Randomizer::pickArrayKeys", rzPickArrayKeys);

    // Random\IntervalBoundary, the interval getFloat() draws from
    var boundary = ClassDef{ .name = "Random\\IntervalBoundary", .is_enum = true, .no_dynamic_properties = true };
    try boundary.properties.append(a, .{ .name = "name", .default = .null, .is_readonly = true, .has_set_visibility = true, .type_str = "string" });
    for (boundary_cases) |name| {
        const case_obj = try a.create(PhpObject);
        case_obj.* = .{ .class_name = "Random\\IntervalBoundary", .enum_case = true };
        try vm.objects.append(a, case_obj);
        try case_obj.set(a, "name", .{ .string = Value.String.borrowed(name) });
        VM.objRetain(case_obj);
        try boundary.constants.put(a, name, .{ .object = case_obj });
        try boundary.constant_order.append(a, name);
        try boundary.case_order.append(a, name);
    }
    try boundary.interfaces.append(a, "UnitEnum");
    try vm.classes.put(a, "Random\\IntervalBoundary", boundary);
    try vm.registerEnumMethods("Random\\IntervalBoundary", 0);

    var mt = ClassDef{ .name = "Random\\Engine\\Mt19937", .is_final = true };
    try mt.interfaces.append(a, "Random\\Engine");
    try mt.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try mt.methods.put(a, "generate", .{ .name = "generate", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\Mt19937", mt);
    try vm.native_fns.put(a, "Random\\Engine\\Mt19937::__construct", mtConstruct);
    try vm.native_fns.put(a, "Random\\Engine\\Mt19937::generate", mtGenerate);

    var pcg = ClassDef{ .name = "Random\\Engine\\PcgOneseq128XslRr64", .is_final = true };
    try pcg.interfaces.append(a, "Random\\Engine");
    try pcg.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try pcg.methods.put(a, "generate", .{ .name = "generate", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\PcgOneseq128XslRr64", pcg);
    try vm.native_fns.put(a, "Random\\Engine\\PcgOneseq128XslRr64::__construct", pcgConstruct);
    try vm.native_fns.put(a, "Random\\Engine\\PcgOneseq128XslRr64::generate", pcgGenerate);

    var xosh = ClassDef{ .name = "Random\\Engine\\Xoshiro256StarStar", .is_final = true };
    try xosh.interfaces.append(a, "Random\\Engine");
    try xosh.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try xosh.methods.put(a, "generate", .{ .name = "generate", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\Xoshiro256StarStar", xosh);
    try vm.native_fns.put(a, "Random\\Engine\\Xoshiro256StarStar::__construct", xoshConstruct);
    try vm.native_fns.put(a, "Random\\Engine\\Xoshiro256StarStar::generate", xoshGenerate);

    var secure = ClassDef{ .name = "Random\\Engine\\Secure", .is_final = true };
    try secure.interfaces.append(a, "Random\\CryptoSafeEngine");
    try secure.interfaces.append(a, "Random\\Engine");
    try secure.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try secure.methods.put(a, "generate", .{ .name = "generate", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\Secure", secure);
    try vm.native_fns.put(a, "Random\\Engine\\Secure::__construct", noopConstruct);
    try vm.native_fns.put(a, "Random\\Engine\\Secure::generate", secureGenerate);
}

fn noopConstruct(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn freshU64FromCrypto() u64 {
    var b: [8]u8 = undefined;
    platform.random.bytes(&b);
    return std.mem.readInt(u64, &b, .little);
}

fn storeState(ctx: *NativeContext, obj: *PhpObject, bytes: []const u8) !void {
    try obj.setCopiedString(ctx.allocator, "_state", bytes);
}

fn loadState(obj: *PhpObject, comptime T: type) ?T {
    const v = obj.get("_state");
    if (v != .string) return null;
    if (v.string.bytes().len != @sizeOf(T)) return null;
    var out: T = undefined;
    @memcpy(std.mem.asBytes(&out), v.string.bytes());
    return out;
}

// ---- Mt19937 ----

fn mtConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const seed_int: u32 = if (args.len >= 1 and args[0] != .null)
        @as(u32, @truncate(@as(u64, @bitCast(Value.toInt(args[0])))))
    else
        @truncate(freshU64FromCrypto());
    const mode: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    if (mode != 0 and mode != 1) {
        try ctx.vm.setPendingException("ValueError", "Random\\Engine\\Mt19937::__construct(): Argument #2 ($mode) must be either MT_RAND_MT19937 or MT_RAND_PHP");
        return error.RuntimeError;
    }
    if (mode == 1) try ctx.vm.raiseError(VM.E_DEPRECATED, "The MT_RAND_PHP variant of Mt19937 is deprecated");
    var m = Mt19937{ .mode = if (mode == 1) .php else .mt19937 };
    m.seed(seed_int);
    try storeState(ctx, this, std.mem.asBytes(&m));
    return NativeResult.scalar(.null);
}

fn mtGenerate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    var m = loadState(this, Mt19937) orelse return NativeResult.scalar(.null);
    const v = m.nextU32();
    try storeState(ctx, this, std.mem.asBytes(&m));
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, v, .little);
    return try NativeResult.copyString(ctx.allocator, &bytes);
}

// ---- PCG OneSeq 128 XSL RR 64 ----

fn pcgConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    var p = PcgOneseq128{};
    if (args.len >= 1 and args[0] != .null) {
        if (args[0] == .string) {
            if (args[0].string.bytes().len != 16) {
                try ctx.vm.setPendingException("ValueError", "Random\\Engine\\PcgOneseq128XslRr64::__construct(): Argument #1 ($seed) must be a 16 byte (128 bit) string");
                return error.RuntimeError;
            }
            _ = p.seedBytes(args[0].string.bytes());
        } else {
            p.seedInt(@bitCast(Value.toInt(args[0])));
        }
    } else {
        p.seedInt(freshU64FromCrypto());
    }
    try storeState(ctx, this, std.mem.asBytes(&p));
    return NativeResult.scalar(.null);
}

fn pcgGenerate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    var p = loadState(this, PcgOneseq128) orelse return NativeResult.scalar(.null);
    const v = p.next();
    try storeState(ctx, this, std.mem.asBytes(&p));
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, v, .little);
    return try NativeResult.copyString(ctx.allocator, &bytes);
}

// ---- Xoshiro256** ----

fn xoshConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    var x = Xoshiro256ss{};
    if (args.len >= 1 and args[0] != .null) {
        if (args[0] == .string) {
            if (args[0].string.bytes().len != 32) {
                try ctx.vm.setPendingException("ValueError", "Random\\Engine\\Xoshiro256StarStar::__construct(): Argument #1 ($seed) must be a 32 byte (256 bit) string");
                return error.RuntimeError;
            }
            _ = x.seedBytes(args[0].string.bytes());
        } else {
            x.seedInt(@bitCast(Value.toInt(args[0])));
        }
    } else {
        x.seedInt(freshU64FromCrypto());
    }
    try storeState(ctx, this, std.mem.asBytes(&x));
    return NativeResult.scalar(.null);
}

fn xoshGenerate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    var x = loadState(this, Xoshiro256ss) orelse return NativeResult.scalar(.null);
    const v = x.next();
    try storeState(ctx, this, std.mem.asBytes(&x));
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, v, .little);
    return try NativeResult.copyString(ctx.allocator, &bytes);
}

fn secureGenerate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    var bytes: [8]u8 = undefined;
    platform.random.bytes(&bytes);
    return try NativeResult.copyString(ctx.allocator, &bytes);
}

// ---- Randomizer dispatch ----

// returns the next u32 from whatever engine the Randomizer was constructed with
fn engineNextU32(ctx: *NativeContext, eng: *PhpObject) u32 {
    if (std.mem.endsWith(u8, eng.class_name, "Mt19937")) {
        var m = loadState(eng, Mt19937) orelse return @as(u32, @truncate(freshU64FromCrypto()));
        const v = m.nextU32();
        storeState(ctx, eng, std.mem.asBytes(&m)) catch {};
        return v;
    }
    if (std.mem.endsWith(u8, eng.class_name, "Xoshiro256StarStar")) {
        var x = loadState(eng, Xoshiro256ss) orelse return @as(u32, @truncate(freshU64FromCrypto()));
        const v = x.next();
        storeState(ctx, eng, std.mem.asBytes(&x)) catch {};
        return @as(u32, @truncate(v));
    }
    if (std.mem.endsWith(u8, eng.class_name, "PcgOneseq128XslRr64")) {
        var p = loadState(eng, PcgOneseq128) orelse return @as(u32, @truncate(freshU64FromCrypto()));
        const v = p.next();
        storeState(ctx, eng, std.mem.asBytes(&p)) catch {};
        return @as(u32, @truncate(v));
    }
    // Secure or unknown: csprng
    return @as(u32, @truncate(freshU64FromCrypto()));
}

fn engineNextU64(ctx: *NativeContext, eng: *PhpObject) u64 {
    if (std.mem.endsWith(u8, eng.class_name, "Mt19937")) {
        // Mt19937 produces 32-bit blocks; PHP consumes two for a u64 with hi
        // word first (matches php_random_algo_mt19937 in php-src)
        var m = loadState(eng, Mt19937) orelse return freshU64FromCrypto();
        const hi: u64 = @as(u64, m.nextU32()) << 32;
        const lo: u64 = @as(u64, m.nextU32());
        storeState(ctx, eng, std.mem.asBytes(&m)) catch {};
        return hi | lo;
    }
    if (std.mem.endsWith(u8, eng.class_name, "Xoshiro256StarStar")) {
        var x = loadState(eng, Xoshiro256ss) orelse return freshU64FromCrypto();
        const v = x.next();
        storeState(ctx, eng, std.mem.asBytes(&x)) catch {};
        return v;
    }
    if (std.mem.endsWith(u8, eng.class_name, "PcgOneseq128XslRr64")) {
        var p = loadState(eng, PcgOneseq128) orelse return freshU64FromCrypto();
        const v = p.next();
        storeState(ctx, eng, std.mem.asBytes(&p)) catch {};
        return v;
    }
    return freshU64FromCrypto();
}

fn engine(ctx: *NativeContext) ?*PhpObject {
    const this = getThis(ctx) orelse return null;
    const v = this.get("_engine");
    if (v != .object) return null;
    return v.object;
}

fn rzConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len >= 1 and args[0] != .null) {
        if (args[0] != .object) {
            try ctx.vm.setPendingException("TypeError", "Random\\Randomizer::__construct(): Argument #1 ($engine) must be of type ?Random\\Engine");
            return error.RuntimeError;
        }
        try this.set(ctx.allocator, "_engine", args[0]);
    }
    return NativeResult.scalar(.null);
}

// PHP's range32 with rejection sampling, using whatever engine is attached
fn rangeU32(ctx: *NativeContext, eng_opt: ?*PhpObject, umax: u32) u32 {
    if (umax == 0xffffffff) {
        return if (eng_opt) |e| engineNextU32(ctx, e) else @as(u32, @truncate(freshU64FromCrypto()));
    }
    const span: u64 = @as(u64, umax) + 1;
    // power-of-two: simple mask
    if ((span & (span - 1)) == 0) {
        const r = if (eng_opt) |e| engineNextU32(ctx, e) else @as(u32, @truncate(freshU64FromCrypto()));
        return @as(u32, @intCast(@as(u64, r) & (span - 1)));
    }
    const limit: u32 = @intCast(0xffffffff - (0xffffffff % span) - 1);
    while (true) {
        const r = if (eng_opt) |e| engineNextU32(ctx, e) else @as(u32, @truncate(freshU64FromCrypto()));
        if (r <= limit) return @as(u32, @intCast(@as(u64, r) % span));
    }
}

fn rangeU64(ctx: *NativeContext, eng_opt: ?*PhpObject, umax: u64) u64 {
    if (umax == 0xffffffffffffffff) {
        return if (eng_opt) |e| engineNextU64(ctx, e) else freshU64FromCrypto();
    }
    const span: u128 = @as(u128, umax) + 1;
    if ((span & (span - 1)) == 0) {
        const r = if (eng_opt) |e| engineNextU64(ctx, e) else freshU64FromCrypto();
        return @intCast(@as(u128, r) & (span - 1));
    }
    const limit_big: u128 = 0x10000000000000000;
    const bound: u64 = @intCast(limit_big - (limit_big % span) - 1);
    while (true) {
        const r = if (eng_opt) |e| engineNextU64(ctx, e) else freshU64FromCrypto();
        if (r <= bound) return @intCast(@as(u128, r) % span);
    }
}

fn rzGetInt(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return NativeResult.scalar(.{ .int = 0 });
    const lo = args[0].int;
    const hi = args[1].int;
    if (hi < lo) {
        try ctx.vm.setPendingException("ValueError", "Random\\Randomizer::getInt(): Argument #2 ($max) must be greater than or equal to argument #1 ($min)");
        return error.RuntimeError;
    }
    if (hi == lo) return NativeResult.scalar(.{ .int = lo });
    const eng_opt = engine(ctx);
    const range: u64 = @intCast(hi - lo);
    if (range <= 0xffffffff) {
        const r: u32 = rangeU32(ctx, eng_opt, @intCast(range));
        return NativeResult.scalar(.{ .int = lo + @as(i64, r) });
    }
    const r: u64 = rangeU64(ctx, eng_opt, range);
    return NativeResult.scalar(.{ .int = lo + @as(i64, @intCast(r)) });
}

fn rzGetBytes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int or args[0].int < 1) return NativeResult.scalar(.{ .bool = false });
    const n: usize = @intCast(args[0].int);
    const buf = try ctx.allocator.alloc(u8, n);
    const eng_opt = engine(ctx);
    var written: usize = 0;
    while (written < n) {
        const v = if (eng_opt) |e| engineNextU64(ctx, e) else freshU64FromCrypto();
        var chunk: [8]u8 = undefined;
        std.mem.writeInt(u64, &chunk, v, .little);
        const take: usize = @min(8, n - written);
        @memcpy(buf[written .. written + take], chunk[0..take]);
        written += take;
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn rzNextInt(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const eng_opt = engine(ctx);
    const v = if (eng_opt) |e| engineNextU64(ctx, e) else freshU64FromCrypto();
    // PHP's nextInt returns a non-negative 63-bit integer
    return NativeResult.scalar(.{ .int = @as(i64, @intCast(v >> 1)) });
}

const boundary_cases = [_][]const u8{ "ClosedOpen", "ClosedClosed", "OpenClosed", "OpenOpen" };
const Boundary = enum { closed_open, closed_closed, open_closed, open_open };

// Randomizer::getFloat: a float drawn uniformly from the interval by the
// gamma-section algorithm (ext/random/gammasection.c), so a seeded engine
// gives php's floats
fn rzGetFloat(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "Random\\Randomizer::getFloat()";
    const min = if (args.len > 0) Value.toFloat(args[0]) else 0.0;
    const max = if (args.len > 1) Value.toFloat(args[1]) else 0.0;
    var boundary: Boundary = .closed_open;
    if (args.len > 2) {
        const arg = args[2];
        if (arg != .object or !std.mem.eql(u8, arg.object.class_name, "Random\\IntervalBoundary")) {
            const msg = try std.fmt.allocPrint(ctx.allocator, label ++ ": Argument #3 ($boundary) must be of type Random\\IntervalBoundary, {s} given", .{@import("types.zig").phpTypeName(arg)});
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("TypeError", msg);
            return error.RuntimeError;
        }
        const name = arg.object.get("name");
        for (boundary_cases, 0..) |case_name, i| {
            if (name == .string and std.mem.eql(u8, name.string.bytes(), case_name)) boundary = @enumFromInt(i);
        }
    }
    if (!std.math.isFinite(min)) return valueError(ctx, label ++ ": Argument #1 ($min) must be finite");
    if (!std.math.isFinite(max)) return valueError(ctx, label ++ ": Argument #2 ($max) must be finite");
    if (boundary == .closed_closed) {
        if (max < min) return valueError(ctx, label ++ ": Argument #2 ($max) must be greater than or equal to argument #1 ($min)");
    } else if (max <= min) return valueError(ctx, label ++ ": Argument #2 ($max) must be greater than argument #1 ($min)");
    const eng = engine(ctx);
    const result = switch (boundary) {
        .closed_open => gammaClosedOpen(ctx, eng, min, max),
        .closed_closed => gammaClosedClosed(ctx, eng, min, max),
        .open_closed => gammaOpenClosed(ctx, eng, min, max),
        .open_open => gammaOpenOpen(ctx, eng, min, max),
    };
    if (boundary == .open_open and std.math.isNan(result)) return valueError(ctx, "The given interval is empty, there are no floats between argument #1 ($min) and argument #2 ($max)");
    return NativeResult.scalar(.{ .float = result });
}

fn valueError(ctx: *NativeContext, msg: []const u8) RuntimeError!NativeResult {
    try ctx.vm.setPendingException("ValueError", msg);
    return error.RuntimeError;
}

fn gammaLow(x: f64) f64 {
    return x - std.math.nextAfter(f64, x, -std.math.floatMax(f64));
}

fn gammaHigh(x: f64) f64 {
    return std.math.nextAfter(f64, x, std.math.floatMax(f64)) - x;
}

fn gammaMax(x: f64, y: f64) f64 {
    return if (@abs(x) > @abs(y)) gammaHigh(x) else gammaLow(y);
}

// (uint64_t) of a non-negative double, saturating where c is undefined
fn toU64(x: f64) u64 {
    if (!(x >= 0)) return 0;
    if (x >= 18446744073709551615.0) return std.math.maxInt(u64);
    return @intFromFloat(x);
}

fn ceilint(a: f64, b: f64, g: f64) u64 {
    const s = b / g - a / g;
    const e = if (@abs(a) <= @abs(b)) -a / g - (s - b / g) else b / g - (s + a / g);
    const si = @ceil(s);
    return if (s != si) toU64(si) else toU64(si) +% @intFromBool(e > 0);
}

// k as php splits it, so k * g keeps its precision: k >> 2 and k & 3
fn scaledFromMax(max: f64, k: u64, g: f64) f64 {
    const k_hi: f64 = @floatFromInt(k >> 2);
    const k_lo: f64 = @floatFromInt(k & 3);
    return 4.0 * (max * 0.25 - k_hi * g) - k_lo * g;
}

fn scaledFromMin(min: f64, k: u64, g: f64) f64 {
    const k_hi: f64 = @floatFromInt(k >> 2);
    const k_lo: f64 = @floatFromInt(k & 3);
    return 4.0 * (min * 0.25 + k_hi * g) + k_lo * g;
}

fn gammaClosedOpen(ctx: *NativeContext, eng: ?*PhpObject, min: f64, max: f64) f64 {
    const g = gammaMax(min, max);
    const hi = ceilint(min, max, g);
    if (max <= min or hi < 1) return std.math.nan(f64);
    const k = 1 + rangeU64(ctx, eng, hi - 1);
    if (@abs(min) <= @abs(max)) {
        if (k == hi) return min;
        return scaledFromMax(max, k, g);
    }
    return scaledFromMin(min, k - 1, g);
}

fn gammaClosedClosed(ctx: *NativeContext, eng: ?*PhpObject, min: f64, max: f64) f64 {
    const g = gammaMax(min, max);
    const hi = ceilint(min, max, g);
    if (max < min) return std.math.nan(f64);
    const k = rangeU64(ctx, eng, hi);
    if (@abs(min) <= @abs(max)) {
        if (k == hi) return min;
        return scaledFromMax(max, k, g);
    }
    if (k == hi) return max;
    return scaledFromMin(min, k, g);
}

fn gammaOpenClosed(ctx: *NativeContext, eng: ?*PhpObject, min: f64, max: f64) f64 {
    const g = gammaMax(min, max);
    const hi = ceilint(min, max, g);
    if (max <= min or hi < 1) return std.math.nan(f64);
    const k = rangeU64(ctx, eng, hi - 1);
    if (@abs(min) <= @abs(max)) return scaledFromMax(max, k, g);
    if (k == hi - 1) return max;
    return scaledFromMin(min, k + 1, g);
}

fn gammaOpenOpen(ctx: *NativeContext, eng: ?*PhpObject, min: f64, max: f64) f64 {
    const g = gammaMax(min, max);
    const hi = ceilint(min, max, g);
    if (max <= min or hi < 2) return std.math.nan(f64);
    const k = 1 + rangeU64(ctx, eng, hi - 2);
    if (@abs(min) <= @abs(max)) return scaledFromMax(max, k, g);
    return scaledFromMin(min, k, g);
}

fn rzNextFloat(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const eng_opt = engine(ctx);
    const v = if (eng_opt) |e| engineNextU64(ctx, e) else freshU64FromCrypto();
    const denom: f64 = @as(f64, @floatFromInt(@as(u64, 1) << 53));
    return NativeResult.scalar(.{ .float = @as(f64, @floatFromInt(v >> 11)) / denom });
}

fn rollN(ctx: *NativeContext, n: usize) usize {
    if (n == 0) return 0;
    const eng_opt = engine(ctx);
    return @intCast(rangeU64(ctx, eng_opt, @as(u64, @intCast(n - 1))));
}

fn rzShuffleArray(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .array) return NativeResult.scalar(.{ .bool = false });
    const src = args[0].array;
    const dst = try ctx.vm.allocArray();
    for (src.entries.items) |e| try dst.append(ctx.allocator, e.value);
    var i: usize = dst.entries.items.len;
    while (i > 1) {
        i -= 1;
        const j = rollN(ctx, i + 1);
        const tmp = dst.entries.items[i].value;
        dst.entries.items[i].value = dst.entries.items[j].value;
        dst.entries.items[j].value = tmp;
    }
    return NativeResult.borrowed(.{ .array = dst });
}

fn rzShuffleBytes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const src = args[0].string.bytes();
    const buf = try ctx.allocator.dupe(u8, src);
    var i: usize = buf.len;
    while (i > 1) {
        i -= 1;
        const j = rollN(ctx, i + 1);
        const tmp = buf[i];
        buf[i] = buf[j];
        buf[j] = tmp;
    }
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, buf));
}

fn rzPickArrayKeys(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .array or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const src = args[0].array;
    const want: usize = @intCast(args[1].int);
    if (want > src.entries.items.len) return NativeResult.scalar(.{ .bool = false });
    const keys = try ctx.allocator.alloc(PhpArray.Key, src.entries.items.len);
    defer ctx.allocator.free(keys);
    for (src.entries.items, 0..) |e, idx| keys[idx] = e.key;
    var i: usize = keys.len;
    while (i > 1) {
        i -= 1;
        const j = rollN(ctx, i + 1);
        const tmp = keys[i];
        keys[i] = keys[j];
        keys[j] = tmp;
    }
    const out = try ctx.vm.allocArray();
    for (keys[0..want]) |k| {
        const v: Value = switch (k) {
            .string => |s| .{ .string = s },
            .int => |n| .{ .int = n },
        };
        try out.append(ctx.allocator, v);
    }
    return NativeResult.borrowed(.{ .array = out });
}
