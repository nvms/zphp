const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const ws = @import("../websocket.zig");
const tls = @import("../tls.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;

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

const WsWriter = struct {
    fd: std.posix.fd_t,
    ssl: ?*tls.SSL,

    pub fn write(self: WsWriter, data: []const u8) !usize {
        if (self.ssl) |s| return tls.write(s, data);
        return std.posix.write(self.fd, data);
    }
};

fn getWriter(obj: *PhpObject) ?WsWriter {
    const fd_val = obj.get("__ws_fd");
    if (fd_val != .int or fd_val.int < 0) return null;
    const ssl_val = obj.get("__ws_ssl");
    const ssl_ptr: ?*tls.SSL = if (ssl_val == .int and ssl_val.int != 0)
        @ptrFromInt(@as(usize, @intCast(ssl_val.int)))
    else
        null;
    return .{ .fd = @intCast(fd_val.int), .ssl = ssl_ptr };
}

fn wsSend(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const closed = obj.get("__ws_closed");
    if (closed == .bool and closed.bool) return NativeResult.scalar(.null);
    var writer = getWriter(obj) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    ws.writeFrame(&writer, .text, args[0].string.bytes()) catch return NativeResult.scalar(.null);
    return NativeResult.scalar(.null);
}

fn wsClose(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const closed = obj.get("__ws_closed");
    if (closed == .bool and closed.bool) return NativeResult.scalar(.null);
    var writer = getWriter(obj) orelse return NativeResult.scalar(.null);
    ws.writeCloseFrame(&writer, 1000) catch {};
    try obj.set(ctx.allocator, "__ws_closed", .{ .bool = true });
    return NativeResult.scalar(.null);
}
