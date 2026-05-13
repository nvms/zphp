const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    var rndmizer = ClassDef{ .name = "Random\\Randomizer" };
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

    // Engine namespace placeholders so `new Random\Engine\Mt19937(42)` parses
    // and the wrapper Randomizer just ignores the engine and uses crypto rand
    var mt = ClassDef{ .name = "Random\\Engine\\Mt19937" };
    try mt.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try mt.methods.put(a, "generate", .{ .name = "generate", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\Mt19937", mt);
    try vm.native_fns.put(a, "Random\\Engine\\Mt19937::__construct", engineConstruct);
    try vm.native_fns.put(a, "Random\\Engine\\Mt19937::generate", engineGenerate);

    var pcg = ClassDef{ .name = "Random\\Engine\\PcgOneseq128XslRr64" };
    try pcg.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try pcg.methods.put(a, "generate", .{ .name = "generate", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\PcgOneseq128XslRr64", pcg);
    try vm.native_fns.put(a, "Random\\Engine\\PcgOneseq128XslRr64::__construct", engineConstruct);
    try vm.native_fns.put(a, "Random\\Engine\\PcgOneseq128XslRr64::generate", engineGenerate);

    var xosh = ClassDef{ .name = "Random\\Engine\\Xoshiro256StarStar" };
    try xosh.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try xosh.methods.put(a, "generate", .{ .name = "generate", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\Xoshiro256StarStar", xosh);
    try vm.native_fns.put(a, "Random\\Engine\\Xoshiro256StarStar::__construct", engineConstruct);
    try vm.native_fns.put(a, "Random\\Engine\\Xoshiro256StarStar::generate", engineGenerate);

    var secure = ClassDef{ .name = "Random\\Engine\\Secure" };
    try secure.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try secure.methods.put(a, "generate", .{ .name = "generate", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\Secure", secure);
    try vm.native_fns.put(a, "Random\\Engine\\Secure::__construct", noopConstruct);
    try vm.native_fns.put(a, "Random\\Engine\\Secure::generate", engineGenerateSecure);
}

// Random\Engine\*::generate(): string. returns 8 raw bytes from the engine's
// PRNG (PHP's contract; the Randomizer wrapper consumes this raw output)
fn engineGenerate(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    var prng = loadPrngFromEngine(this) orelse return .null;
    var bytes: [8]u8 = undefined;
    prng.random().bytes(&bytes);
    try savePrngToEngine(ctx, this, &prng);
    const owned = try ctx.allocator.dupe(u8, &bytes);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn engineGenerateSecure(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    var bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    const owned = try ctx.allocator.dupe(u8, &bytes);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn noopConstruct(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

// engine __construct: seed an Xoshiro256 PRNG and store its raw state on $this.
// every supported engine class shares this implementation; exact algorithm
// differs from PHP's Mt19937/PCG but reproducibility per-seed is preserved
fn engineConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const seed: u64 = if (args.len >= 1) @bitCast(Value.toInt(args[0])) else @intCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const bytes = std.mem.asBytes(&prng);
    const owned = try ctx.allocator.dupe(u8, bytes);
    try ctx.vm.strings.append(ctx.allocator, owned);
    try this.set(ctx.allocator, "_state", .{ .string = owned });
    return .null;
}

fn engineIsSecure(obj: *PhpObject) bool {
    return std.mem.endsWith(u8, obj.class_name, "Secure");
}

fn loadPrngFromEngine(engine: *PhpObject) ?std.Random.DefaultPrng {
    const v = engine.get("_state");
    if (v != .string) return null;
    if (v.string.len != @sizeOf(std.Random.DefaultPrng)) return null;
    var prng: std.Random.DefaultPrng = undefined;
    @memcpy(std.mem.asBytes(&prng), v.string);
    return prng;
}

fn savePrngToEngine(ctx: *NativeContext, engine: *PhpObject, prng: *const std.Random.DefaultPrng) !void {
    const bytes = std.mem.asBytes(prng);
    const owned = try ctx.allocator.dupe(u8, bytes);
    try ctx.vm.strings.append(ctx.allocator, owned);
    try engine.set(ctx.allocator, "_state", .{ .string = owned });
}

// returns the engine object referenced by the Randomizer ($this->_engine), or
// null when the engine is Secure / unset (callers should fall back to crypto)
fn randEngine(ctx: *NativeContext) ?*PhpObject {
    const this = getThis(ctx) orelse return null;
    const v = this.get("_engine");
    if (v != .object) return null;
    if (engineIsSecure(v.object)) return null;
    return v.object;
}

fn rzConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    if (args.len >= 1 and args[0] == .object) {
        try this.set(ctx.allocator, "_engine", args[0]);
    }
    return .null;
}

fn rzGetBytes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int or args[0].int < 1) return .{ .bool = false };
    const n: usize = @intCast(args[0].int);
    const buf = try ctx.allocator.alloc(u8, n);
    if (randEngine(ctx)) |eng| {
        if (loadPrngFromEngine(eng)) |loaded| {
            var prng = loaded;
            prng.random().bytes(buf);
            try savePrngToEngine(ctx, eng, &prng);
        } else std.crypto.random.bytes(buf);
    } else std.crypto.random.bytes(buf);
    try ctx.vm.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn rzGetInt(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return .{ .int = 0 };
    const lo = args[0].int;
    const hi = args[1].int;
    if (hi < lo) return .{ .int = lo };
    const span: u64 = @intCast(hi - lo + 1);
    var r: u64 = 0;
    if (randEngine(ctx)) |eng| {
        if (loadPrngFromEngine(eng)) |loaded| {
            var prng = loaded;
            r = prng.random().uintLessThan(u64, span);
            savePrngToEngine(ctx, eng, &prng) catch {};
        } else r = std.crypto.random.uintLessThan(u64, span);
    } else r = std.crypto.random.uintLessThan(u64, span);
    return .{ .int = lo + @as(i64, @intCast(r)) };
}

fn rzNextInt(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (randEngine(ctx)) |eng| {
        if (loadPrngFromEngine(eng)) |loaded| {
            var prng = loaded;
            const v: i63 = @bitCast(@as(u63, @truncate(prng.random().int(u64))));
            savePrngToEngine(ctx, eng, &prng) catch {};
            return .{ .int = v };
        }
    }
    return .{ .int = std.crypto.random.int(i63) };
}

fn rzGetFloat(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    var lo: f64 = 0.0;
    var hi: f64 = 1.0;
    if (args.len >= 2 and args[0] != .null) lo = Value.toFloat(args[0]);
    if (args.len >= 2 and args[1] != .null) hi = Value.toFloat(args[1]);
    if (hi <= lo) return .{ .float = lo };
    var r: f64 = 0;
    if (randEngine(ctx)) |eng| {
        if (loadPrngFromEngine(eng)) |loaded| {
            var prng = loaded;
            r = prng.random().float(f64);
            savePrngToEngine(ctx, eng, &prng) catch {};
        } else r = std.crypto.random.float(f64);
    } else r = std.crypto.random.float(f64);
    return .{ .float = lo + r * (hi - lo) };
}

fn rzNextFloat(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    if (randEngine(ctx)) |eng| {
        if (loadPrngFromEngine(eng)) |loaded| {
            var prng = loaded;
            const r = prng.random().float(f64);
            savePrngToEngine(ctx, eng, &prng) catch {};
            return .{ .float = r };
        }
    }
    return .{ .float = std.crypto.random.float(f64) };
}

// roll a uniform integer in [0, n) using either the engine's PRNG or crypto
fn rollN(ctx: *NativeContext, n: usize) usize {
    if (randEngine(ctx)) |eng| {
        if (loadPrngFromEngine(eng)) |loaded| {
            var prng = loaded;
            const r = prng.random().uintLessThan(usize, n);
            savePrngToEngine(ctx, eng, &prng) catch {};
            return r;
        }
    }
    return std.crypto.random.uintLessThan(usize, n);
}

fn rzShuffleArray(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .array) return .{ .bool = false };
    const src = args[0].array;
    const dst = try ctx.allocator.create(PhpArray);
    dst.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, dst);
    for (src.entries.items) |e| try dst.append(ctx.allocator, e.value);
    var i: usize = dst.entries.items.len;
    while (i > 1) {
        i -= 1;
        const j = rollN(ctx, i + 1);
        const tmp = dst.entries.items[i].value;
        dst.entries.items[i].value = dst.entries.items[j].value;
        dst.entries.items[j].value = tmp;
    }
    return .{ .array = dst };
}

fn rzShuffleBytes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const src = args[0].string;
    const buf = try ctx.allocator.dupe(u8, src);
    var i: usize = buf.len;
    while (i > 1) {
        i -= 1;
        const j = rollN(ctx, i + 1);
        const tmp = buf[i];
        buf[i] = buf[j];
        buf[j] = tmp;
    }
    try ctx.vm.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn rzPickArrayKeys(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array or args[1] != .int) return .{ .bool = false };
    const src = args[0].array;
    const want: usize = @intCast(args[1].int);
    if (want > src.entries.items.len) return .{ .bool = false };
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
    const out = try ctx.allocator.create(PhpArray);
    out.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, out);
    for (keys[0..want]) |k| {
        const v: Value = switch (k) {
            .string => |s| .{ .string = s },
            .int => |n| .{ .int = n },
        };
        try out.append(ctx.allocator, v);
    }
    return .{ .array = out };
}
