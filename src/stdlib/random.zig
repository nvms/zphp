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
    try vm.classes.put(a, "Random\\Engine\\Mt19937", mt);
    try vm.native_fns.put(a, "Random\\Engine\\Mt19937::__construct", noopConstruct);

    var pcg = ClassDef{ .name = "Random\\Engine\\PcgOneseq128XslRr64" };
    try pcg.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try vm.classes.put(a, "Random\\Engine\\PcgOneseq128XslRr64", pcg);
    try vm.native_fns.put(a, "Random\\Engine\\PcgOneseq128XslRr64::__construct", noopConstruct);

    var xosh = ClassDef{ .name = "Random\\Engine\\Xoshiro256StarStar" };
    try xosh.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try vm.classes.put(a, "Random\\Engine\\Xoshiro256StarStar", xosh);
    try vm.native_fns.put(a, "Random\\Engine\\Xoshiro256StarStar::__construct", noopConstruct);

    var secure = ClassDef{ .name = "Random\\Engine\\Secure" };
    try secure.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try vm.classes.put(a, "Random\\Engine\\Secure", secure);
    try vm.native_fns.put(a, "Random\\Engine\\Secure::__construct", noopConstruct);
}

fn noopConstruct(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn rzConstruct(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn rzGetBytes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int or args[0].int < 1) return .{ .bool = false };
    const n: usize = @intCast(args[0].int);
    const buf = try ctx.allocator.alloc(u8, n);
    std.crypto.random.bytes(buf);
    try ctx.vm.strings.append(ctx.allocator, buf);
    return .{ .string = buf };
}

fn rzGetInt(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return .{ .int = 0 };
    const lo = args[0].int;
    const hi = args[1].int;
    if (hi < lo) return .{ .int = lo };
    const span: u64 = @intCast(hi - lo + 1);
    const r = std.crypto.random.uintLessThan(u64, span);
    return .{ .int = lo + @as(i64, @intCast(r)) };
}

fn rzNextInt(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = std.crypto.random.int(i63) };
}

fn rzGetFloat(_: *NativeContext, args: []const Value) RuntimeError!Value {
    var lo: f64 = 0.0;
    var hi: f64 = 1.0;
    if (args.len >= 2 and args[0] != .null) lo = Value.toFloat(args[0]);
    if (args.len >= 2 and args[1] != .null) hi = Value.toFloat(args[1]);
    if (hi <= lo) return .{ .float = lo };
    const r = std.crypto.random.float(f64);
    return .{ .float = lo + r * (hi - lo) };
}

fn rzNextFloat(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .float = std.crypto.random.float(f64) };
}

fn rzShuffleArray(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .array) return .{ .bool = false };
    const src = args[0].array;
    const dst = try ctx.allocator.create(PhpArray);
    dst.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, dst);
    // copy values, then Fisher-Yates shuffle
    for (src.entries.items) |e| try dst.append(ctx.allocator, e.value);
    var i: usize = dst.entries.items.len;
    while (i > 1) {
        i -= 1;
        const j = std.crypto.random.uintLessThan(usize, i + 1);
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
        const j = std.crypto.random.uintLessThan(usize, i + 1);
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
    // collect keys, shuffle, take first `want`
    const keys = try ctx.allocator.alloc(PhpArray.Key, src.entries.items.len);
    defer ctx.allocator.free(keys);
    for (src.entries.items, 0..) |e, idx| keys[idx] = e.key;
    var i: usize = keys.len;
    while (i > 1) {
        i -= 1;
        const j = std.crypto.random.uintLessThan(usize, i + 1);
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
