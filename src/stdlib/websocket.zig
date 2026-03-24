const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const ws = @import("../websocket.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "WebSocketConnection" };
    try def.methods.put(a, "send", .{ .name = "send", .arity = 1 });
    try def.methods.put(a, "close", .{ .name = "close", .arity = 0 });
    try vm.classes.put(a, "WebSocketConnection", def);

    try vm.native_fns.put(a, "WebSocketConnection::send", wsSend);
    try vm.native_fns.put(a, "WebSocketConnection::close", wsClose);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getStream(obj: *PhpObject) ?std.net.Stream {
    const v = obj.get("__ws_fd");
    if (v != .int or v.int < 0) return null;
    return std.net.Stream{ .handle = @intCast(v.int) };
}

fn wsSend(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const closed = obj.get("__ws_closed");
    if (closed == .bool and closed.bool) return .null;
    const stream = getStream(obj) orelse return .null;
    if (args.len < 1 or args[0] != .string) return .null;
    ws.writeFrame(stream, .text, args[0].string) catch return .null;
    return .null;
}

fn wsClose(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const closed = obj.get("__ws_closed");
    if (closed == .bool and closed.bool) return .null;
    const stream = getStream(obj) orelse return .null;
    ws.writeCloseFrame(stream, 1000) catch {};
    try obj.set(ctx.allocator, "__ws_closed", .{ .bool = true });
    return .null;
}
