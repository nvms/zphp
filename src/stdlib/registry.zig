const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!Value;

pub fn register(map: *std.StringHashMapUnmanaged(NativeFn), allocator: std.mem.Allocator) !void {
    const modules = .{
        @import("types.zig").entries,
        @import("math.zig").entries,
        @import("strings.zig").entries,
        @import("arrays.zig").entries,
        @import("json.zig").entries,
        @import("io.zig").entries,
        @import("pcre.zig").entries,
        @import("testing.zig").entries,
    };
    inline for (modules) |entries| {
        inline for (entries) |f| try map.put(allocator, f[0], f[1]);
    }
}

test {
    _ = @import("types.zig");
    _ = @import("math.zig");
    _ = @import("strings.zig");
    _ = @import("arrays.zig");
    _ = @import("json.zig");
    _ = @import("io.zig");
    _ = @import("pcre.zig");
    _ = @import("testing.zig");
}
