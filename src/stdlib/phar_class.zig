const std = @import("std");
const phar = @import("phar.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "Phar" };
    try def.interfaces.append(a, "Countable");
    try def.interfaces.append(a, "ArrayAccess");
    try def.interfaces.append(a, "Iterator");
    for ([_]struct { name: []const u8, value: i64 }{
        .{ .name = "BZ2", .value = 8192 },          .{ .name = "GZ", .value = 4096 },
        .{ .name = "NONE", .value = 0 },            .{ .name = "PHAR", .value = 1 },
        .{ .name = "TAR", .value = 2 },             .{ .name = "ZIP", .value = 3 },
        .{ .name = "MD5", .value = 1 },             .{ .name = "SHA1", .value = 2 },
        .{ .name = "SHA256", .value = 3 },          .{ .name = "SHA512", .value = 4 },
        .{ .name = "OPENSSL", .value = 16 },        .{ .name = "OPENSSL_SHA256", .value = 17 },
        .{ .name = "OPENSSL_SHA512", .value = 18 },
    }) |constant| try def.static_props.put(a, constant.name, .{ .int = constant.value });

    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try def.methods.put(a, "addFromString", .{ .name = "addFromString", .arity = 2 });
    try def.methods.put(a, "addFile", .{ .name = "addFile", .arity = 1 });
    try def.methods.put(a, "setStub", .{ .name = "setStub", .arity = 1 });
    try def.methods.put(a, "getStub", .{ .name = "getStub", .arity = 0 });
    try def.methods.put(a, "getAlias", .{ .name = "getAlias", .arity = 0 });
    try def.methods.put(a, "setAlias", .{ .name = "setAlias", .arity = 1 });
    try def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try def.methods.put(a, "delete", .{ .name = "delete", .arity = 1 });
    try def.methods.put(a, "startBuffering", .{ .name = "startBuffering", .arity = 0 });
    try def.methods.put(a, "stopBuffering", .{ .name = "stopBuffering", .arity = 0 });
    try def.methods.put(a, "getPath", .{ .name = "getPath", .arity = 0 });
    try def.methods.put(a, "isWritable", .{ .name = "isWritable", .arity = 0 });
    try def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try def.methods.put(a, "getMetadata", .{ .name = "getMetadata", .arity = 0 });
    try def.methods.put(a, "setMetadata", .{ .name = "setMetadata", .arity = 1 });
    try def.methods.put(a, "hasMetadata", .{ .name = "hasMetadata", .arity = 0 });
    try def.methods.put(a, "canWrite", .{ .name = "canWrite", .arity = 0, .is_static = true });
    try def.methods.put(a, "canCompress", .{ .name = "canCompress", .arity = 1, .is_static = true });
    try def.methods.put(a, "running", .{ .name = "running", .arity = 1, .is_static = true });
    try def.methods.put(a, "loadPhar", .{ .name = "loadPhar", .arity = 2, .is_static = true });
    try def.methods.put(a, "getSupportedCompression", .{ .name = "getSupportedCompression", .arity = 0, .is_static = true });
    try def.methods.put(a, "getSupportedSignatures", .{ .name = "getSupportedSignatures", .arity = 0, .is_static = true });
    try def.methods.put(a, "isValidPharFilename", .{ .name = "isValidPharFilename", .arity = 2, .is_static = true });
    try def.methods.put(a, "mungServer", .{ .name = "mungServer", .arity = 1, .is_static = true });
    try def.methods.put(a, "unlinkArchive", .{ .name = "unlinkArchive", .arity = 1, .is_static = true });
    try def.methods.put(a, "interceptFileFuncs", .{ .name = "interceptFileFuncs", .arity = 0, .is_static = true });
    try def.methods.put(a, "mapPhar", .{ .name = "mapPhar", .arity = 2, .is_static = true });

    try vm.classes.put(a, "Phar", def);

    try vm.native_fns.put(a, "Phar::__construct", phConstruct);
    try vm.native_fns.put(a, "Phar::addFromString", phAddFromString);
    try vm.native_fns.put(a, "Phar::addFile", phAddFile);
    try vm.native_fns.put(a, "Phar::setStub", phSetStub);
    try vm.native_fns.put(a, "Phar::getStub", phGetStub);
    try vm.native_fns.put(a, "Phar::getAlias", phGetAlias);
    try vm.native_fns.put(a, "Phar::setAlias", phSetAlias);
    try vm.native_fns.put(a, "Phar::count", phCount);
    try vm.native_fns.put(a, "Phar::offsetExists", phOffsetExists);
    try vm.native_fns.put(a, "Phar::offsetGet", phOffsetGet);
    try vm.native_fns.put(a, "Phar::offsetSet", phOffsetSet);
    try vm.native_fns.put(a, "Phar::offsetUnset", phOffsetUnset);
    try vm.native_fns.put(a, "Phar::delete", phOffsetUnset);
    try vm.native_fns.put(a, "Phar::startBuffering", phStartBuffering);
    try vm.native_fns.put(a, "Phar::stopBuffering", phStopBuffering);
    try vm.native_fns.put(a, "Phar::getPath", phGetPath);
    try vm.native_fns.put(a, "Phar::isWritable", phIsWritable);
    try vm.native_fns.put(a, "Phar::rewind", phRewind);
    try vm.native_fns.put(a, "Phar::valid", phValid);
    try vm.native_fns.put(a, "Phar::key", phKey);
    try vm.native_fns.put(a, "Phar::current", phCurrent);
    try vm.native_fns.put(a, "Phar::next", phNext);
    try vm.native_fns.put(a, "Phar::getMetadata", phGetMetadata);
    try vm.native_fns.put(a, "Phar::setMetadata", phSetMetadata);
    try vm.native_fns.put(a, "Phar::hasMetadata", phHasMetadata);
    try vm.native_fns.put(a, "Phar::canWrite", phCanWrite);
    try vm.native_fns.put(a, "Phar::canCompress", phCanCompress);
    try vm.native_fns.put(a, "Phar::running", phRunning);
    try vm.native_fns.put(a, "Phar::loadPhar", phLoadPhar);
    try vm.native_fns.put(a, "Phar::getSupportedCompression", phGetSupportedCompression);
    try vm.native_fns.put(a, "Phar::getSupportedSignatures", phGetSupportedSignatures);
    try vm.native_fns.put(a, "Phar::isValidPharFilename", phIsValidPharFilename);
    try vm.native_fns.put(a, "Phar::mungServer", phMungServer);
    try vm.native_fns.put(a, "Phar::unlinkArchive", phUnlinkArchive);
    try vm.native_fns.put(a, "Phar::interceptFileFuncs", phInterceptFileFuncs);
    try vm.native_fns.put(a, "Phar::mapPhar", phMapPhar);

    // stub classes so class_exists and instanceof work even without the full
    // Phar feature surface behind them
    var pd_def = ClassDef{ .name = "PharData" };
    pd_def.parent = "Phar";
    try vm.classes.put(a, "PharData", pd_def);

    var pfi_def = ClassDef{ .name = "PharFileInfo" };
    pfi_def.parent = "SplFileInfo";
    try vm.classes.put(a, "PharFileInfo", pfi_def);

    var pe_def = ClassDef{ .name = "PharException" };
    pe_def.parent = "Exception";
    try vm.classes.put(a, "PharException", pe_def);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn ensureEntries(ctx: *NativeContext, obj: *PhpObject) !*PhpArray {
    const v = obj.get("__entries");
    if (v == .array) return v.array;
    const arr = try ctx.allocator.create(PhpArray);
    arr.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, arr);
    try obj.set(ctx.allocator, "__entries", .{ .array = arr });
    return arr;
}

fn getEntries(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__entries");
    if (v == .array) return v.array;
    return null;
}

fn dupString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const owned = try ctx.allocator.dupe(u8, s);
    try ctx.strings.append(ctx.allocator, owned);
    return owned;
}

fn phConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const filename = try dupString(ctx, args[0].string.bytes());
    try obj.set(ctx.allocator, "__filename", .{ .string = Value.String.borrowed(filename) });
    try obj.set(ctx.allocator, "__stub", .{ .string = Value.String.borrowed(phar.default_stub) });
    try obj.set(ctx.allocator, "__alias", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__buffering", .{ .bool = false });
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    _ = try ensureEntries(ctx, obj);

    // if file exists, parse it and load entries
    const cwd = std.fs.cwd();
    const file = cwd.openFile(filename, .{}) catch |e| switch (e) {
        error.FileNotFound => return NativeResult.scalar(.null),
        else => return NativeResult.scalar(.null),
    };
    defer file.close();
    const stat = file.stat() catch return NativeResult.scalar(.null);
    const bytes = ctx.allocator.alloc(u8, @intCast(stat.size)) catch return NativeResult.scalar(.null);
    defer ctx.allocator.free(bytes);
    _ = file.readAll(bytes) catch return NativeResult.scalar(.null);

    var parsed = phar.parse(ctx.allocator, bytes) catch return NativeResult.scalar(.null);
    defer parsed.deinit(ctx.allocator);

    // capture stub: bytes before manifest start
    const halt_idx = std.mem.indexOf(u8, bytes, phar.HALT_TOKEN);
    if (halt_idx) |hidx| {
        var end = hidx + phar.HALT_TOKEN.len;
        while (end < bytes.len and (bytes[end] == ' ' or bytes[end] == '\t')) end += 1;
        if (end + 2 <= bytes.len and bytes[end] == '?' and bytes[end + 1] == '>') end += 2;
        if (end < bytes.len and bytes[end] == '\r') end += 1;
        if (end < bytes.len and bytes[end] == '\n') end += 1;
        const stub_copy = try dupString(ctx, bytes[0..end]);
        try obj.set(ctx.allocator, "__stub", .{ .string = Value.String.borrowed(stub_copy) });
    }

    const entries_arr = try ensureEntries(ctx, obj);
    var it = parsed.entries.iterator();
    while (it.next()) |kv| {
        const data = phar.extract(ctx.allocator, &parsed, kv.value_ptr.*) catch continue;
        try ctx.strings.append(ctx.allocator, data);
        const name_copy = try dupString(ctx, kv.key_ptr.*);
        try entries_arr.set(ctx.allocator, .{ .string = Value.String.borrowed(name_copy) }, .{ .string = Value.String.borrowed(data) });
    }
    return NativeResult.scalar(.null);
}

fn phAddFromString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 2) return NativeResult.scalar(.null);
    if (args[0] != .string) return NativeResult.scalar(.null);
    const name_str = try dupString(ctx, args[0].string.bytes());
    const content = if (args[1] == .string) try dupString(ctx, args[1].string.bytes()) else "";
    const arr = try ensureEntries(ctx, obj);
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(name_str) }, .{ .string = Value.String.borrowed(content) });
    try saveIfNotBuffering(ctx, obj);
    return NativeResult.scalar(.null);
}

fn phAddFile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const path = args[0].string.bytes();
    const local_name = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else std.fs.path.basename(path);

    const cwd = std.fs.cwd();
    const file = cwd.openFile(path, .{}) catch return NativeResult.scalar(.null);
    defer file.close();
    const stat = file.stat() catch return NativeResult.scalar(.null);
    const buf = ctx.allocator.alloc(u8, @intCast(stat.size)) catch return NativeResult.scalar(.null);
    _ = file.readAll(buf) catch {
        ctx.allocator.free(buf);
        return NativeResult.scalar(.null);
    };
    try ctx.strings.append(ctx.allocator, buf);

    const arr = try ensureEntries(ctx, obj);
    const name_str = try dupString(ctx, local_name);
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(name_str) }, .{ .string = Value.String.borrowed(buf) });
    try saveIfNotBuffering(ctx, obj);
    return NativeResult.scalar(.null);
}

fn phSetStub(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const stub = try dupString(ctx, args[0].string.bytes());
    try obj.set(ctx.allocator, "__stub", .{ .string = Value.String.borrowed(stub) });
    try saveIfNotBuffering(ctx, obj);
    return NativeResult.scalar(.{ .bool = true });
}

fn phGetStub(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    return NativeResult.share(obj.get("__stub"));
}

fn phGetAlias(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const v = obj.get("__alias");
    if (v == .string and v.string.bytes().len == 0) return NativeResult.scalar(.null);
    return NativeResult.share(v);
}

fn phSetAlias(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const alias = try dupString(ctx, args[0].string.bytes());
    try obj.set(ctx.allocator, "__alias", .{ .string = Value.String.borrowed(alias) });
    try saveIfNotBuffering(ctx, obj);
    return NativeResult.scalar(.{ .bool = true });
}

fn phCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arr = getEntries(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = arr.length() });
}

fn phOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const arr = getEntries(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (arr.string_index.contains(args[0].string.bytes())) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = false });
}

fn phOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const arr = getEntries(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(arr.get(.{ .string = args[0].string }));
}

fn phOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.null);
    const name = try dupString(ctx, args[0].string.bytes());
    const content = if (args[1] == .string) try dupString(ctx, args[1].string.bytes()) else "";
    const arr = try ensureEntries(ctx, obj);
    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, .{ .string = Value.String.borrowed(content) });
    try saveIfNotBuffering(ctx, obj);
    return NativeResult.scalar(.null);
}

fn phOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const arr = getEntries(obj) orelse return NativeResult.scalar(.null);
    arr.remove(.{ .string = args[0].string });
    try saveIfNotBuffering(ctx, obj);
    return NativeResult.scalar(.null);
}

fn phStartBuffering(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__buffering", .{ .bool = true });
    return NativeResult.scalar(.null);
}

fn phStopBuffering(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__buffering", .{ .bool = false });
    try saveAll(ctx, obj);
    return NativeResult.scalar(.null);
}

fn phGetPath(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    return NativeResult.share(obj.get("__filename"));
}

fn phIsWritable(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn phRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn phValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const cursor = obj.get("__cursor");
    const arr = getEntries(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (cursor != .int) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cursor.int >= 0 and cursor.int < arr.length() });
}

fn phKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cursor = obj.get("__cursor");
    const arr = getEntries(obj) orelse return NativeResult.scalar(.null);
    if (cursor != .int) return NativeResult.scalar(.null);
    const idx: usize = @intCast(cursor.int);
    if (idx >= arr.entries.items.len) return NativeResult.scalar(.null);
    const key = arr.entries.items[idx].key;
    return switch (key) {
        .string => |s| NativeResult.shareString(s),
        .int => |i| NativeResult.scalar(.{ .int = i }),
    };
}

fn phCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cursor = obj.get("__cursor");
    const arr = getEntries(obj) orelse return NativeResult.scalar(.null);
    if (cursor != .int) return NativeResult.scalar(.null);
    const idx: usize = @intCast(cursor.int);
    if (idx >= arr.entries.items.len) return NativeResult.scalar(.null);
    return NativeResult.share(arr.entries.items[idx].value);
}

fn phNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cursor = obj.get("__cursor");
    const next_val: i64 = if (cursor == .int) cursor.int + 1 else 0;
    try obj.set(ctx.allocator, "__cursor", .{ .int = next_val });
    return NativeResult.scalar(.null);
}

fn phGetMetadata(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__metadata"));
}

fn phSetMetadata(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__metadata", args[0]);
    return NativeResult.scalar(.null);
}

fn phHasMetadata(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = obj.get("__metadata");
    return NativeResult.scalar(.{ .bool = v != .null });
}

fn phCanWrite(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // Phar::canWrite() reports whether the phar.readonly ini setting allows
    // writing. zphp doesn't enforce that flag and always writes
    return NativeResult.scalar(.{ .bool = true });
}

fn phCanCompress(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0) return NativeResult.scalar(.{ .bool = true });
    if (args[0] != .int) return NativeResult.scalar(.{ .bool = false });
    // 4096 = Phar::GZ (we support), 8192 = Phar::BZ2 (we don't)
    return NativeResult.scalar(.{ .bool = args[0].int == 0 or args[0].int == 4096 });
}

fn phRunning(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // returns the path to the currently-executing phar, or "" when not running from one
    _ = ctx;
    return NativeResult.literal("");
}

fn phLoadPhar(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn phGetSupportedCompression(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("GZ") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn phGetSupportedSignatures(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("MD5") });
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("SHA-1") });
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("SHA-256") });
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("SHA-512") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn phIsValidPharFilename(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    return NativeResult.scalar(.{ .bool = std.mem.endsWith(u8, name, ".phar") or std.mem.endsWith(u8, name, ".phar.gz") });
}

fn phMungServer(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn phUnlinkArchive(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    std.fs.cwd().deleteFile(args[0].string.bytes()) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn phInterceptFileFuncs(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn phMapPhar(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // `Phar::mapPhar('alias')` registers an alias for the currently-running
    // phar file so subsequent `phar://alias/...` reads resolve to it
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = true });
    const alias = args[0].string.bytes();
    const fp = ctx.vm.file_path;
    if (fp.len == 0) return NativeResult.scalar(.{ .bool = true });
    const resolved_fp = std.fs.cwd().realpathAlloc(ctx.allocator, fp) catch try ctx.allocator.dupe(u8, fp);
    defer ctx.allocator.free(resolved_fp);
    const alias_dup = try ctx.allocator.dupe(u8, alias);
    const fp_dup = try ctx.allocator.dupe(u8, resolved_fp);
    try ctx.vm.strings.append(ctx.allocator, alias_dup);
    try ctx.vm.strings.append(ctx.allocator, fp_dup);
    try ctx.vm.phar_aliases.put(ctx.allocator, alias_dup, fp_dup);
    return NativeResult.scalar(.{ .bool = true });
}

fn saveIfNotBuffering(ctx: *NativeContext, obj: *PhpObject) !void {
    const buf = obj.get("__buffering");
    if (buf == .bool and buf.bool) return;
    try saveAll(ctx, obj);
}

fn saveAll(ctx: *NativeContext, obj: *PhpObject) !void {
    const filename_v = obj.get("__filename");
    if (filename_v != .string) return;
    const stub_v = obj.get("__stub");
    const stub: []const u8 = if (stub_v == .string) stub_v.string.bytes() else phar.default_stub;
    const alias_v = obj.get("__alias");
    const alias: []const u8 = if (alias_v == .string) alias_v.string.bytes() else "";

    const arr = getEntries(obj) orelse return;
    var entries = std.ArrayListUnmanaged(phar.WriteEntry){};
    defer entries.deinit(ctx.allocator);
    for (arr.entries.items) |entry| {
        const name = switch (entry.key) {
            .string => |s| s.bytes(),
            .int => continue,
        };
        const content = if (entry.value == .string) entry.value.string.bytes() else "";
        try entries.append(ctx.allocator, .{
            .name = name,
            .contents = content,
            .timestamp = @intCast(@as(u64, @intCast(std.time.timestamp())) & 0xFFFFFFFF),
        });
    }

    const bytes = phar.write(ctx.allocator, stub, alias, entries.items) catch return;
    defer ctx.allocator.free(bytes);

    const cwd = std.fs.cwd();
    const file = cwd.createFile(filename_v.string.bytes(), .{ .truncate = true }) catch return;
    defer file.close();
    file.writeAll(bytes) catch return;
}

test "phar write and parse roundtrip" {
    const a = std.testing.allocator;
    const entries = [_]phar.WriteEntry{
        .{ .name = "a.txt", .contents = "hello" },
        .{ .name = "lib/b.php", .contents = "<?php echo 1;" },
    };
    const bytes = try phar.write(a, phar.default_stub, "", &entries);
    defer a.free(bytes);

    var parsed = try phar.parse(a, bytes);
    defer parsed.deinit(a);

    try std.testing.expectEqual(@as(usize, 2), parsed.entries.count());
    const e1 = parsed.lookup("a.txt").?;
    const c1 = try phar.extract(a, &parsed, e1);
    defer a.free(c1);
    try std.testing.expectEqualStrings("hello", c1);
    const e2 = parsed.lookup("lib/b.php").?;
    const c2 = try phar.extract(a, &parsed, e2);
    defer a.free(c2);
    try std.testing.expectEqualStrings("<?php echo 1;", c2);
}

test "phar write with gz compression" {
    const a = std.testing.allocator;
    const entries = [_]phar.WriteEntry{
        .{
            .name = "data.txt",
            .contents = "compress me compress me compress me",
            .compress = phar.COMPRESSED_GZ,
        },
    };
    const bytes = try phar.write(a, phar.default_stub, "", &entries);
    defer a.free(bytes);

    var parsed = try phar.parse(a, bytes);
    defer parsed.deinit(a);

    const e = parsed.lookup("data.txt").?;
    const c = try phar.extract(a, &parsed, e);
    defer a.free(c);
    try std.testing.expectEqualStrings("compress me compress me compress me", c);
}
