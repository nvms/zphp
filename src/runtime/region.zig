const std = @import("std");
const sys = @import("../sys.zig");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;
const win32 = @import("../win32.zig");

// address space for up to `capacity` items, made usable a prefix at a time.
// the base never moves, so pointers and slices into the committed part stay
// valid while it grows, and touching past the committed part faults instead
// of reaching other memory
pub fn Region(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T = &.{},
        committed: usize = 0,

        pub fn reserve(capacity: usize) !Self {
            const bytes = std.mem.alignForward(usize, capacity * @sizeOf(T), std.heap.pageSize());
            const base: [*]align(@alignOf(T)) u8 = if (is_windows) blk: {
                const addr = win32.VirtualAlloc(null, bytes, win32.MEM_RESERVE, win32.PAGE_NOACCESS) orelse return error.OutOfMemory;
                break :blk @ptrCast(@alignCast(addr));
            } else blk: {
                const mapped = try std.posix.mmap(null, bytes, .{}, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
                break :blk @ptrCast(@alignCast(mapped.ptr));
            };
            return .{ .items = @as([*]T, @ptrCast(base))[0 .. bytes / @sizeOf(T)] };
        }

        // makes the first `count` items usable; false when that is past the
        // reservation
        pub fn ensure(self: *Self, count: usize) !bool {
            if (count <= self.committed) return true;
            if (count > self.items.len) return false;
            const page = std.heap.pageSize();
            const start = self.committed * @sizeOf(T) / page * page;
            const end = @min(std.mem.alignForward(usize, count * @sizeOf(T), page), self.items.len * @sizeOf(T));
            const base: [*]u8 = @ptrCast(self.items.ptr);
            if (is_windows) {
                _ = win32.VirtualAlloc(@ptrCast(base + start), end - start, win32.MEM_COMMIT, win32.PAGE_READWRITE) orelse return error.OutOfMemory;
            } else {
                const span: []align(std.heap.page_size_min) u8 = @alignCast(base[start..end]);
                try sys.mprotect(span, .{ .READ = true, .WRITE = true });
            }
            self.committed = end / @sizeOf(T);
            return true;
        }

        // ensure, then give the newly usable items a starting value
        pub fn ensureFilled(self: *Self, count: usize, fill: T) !bool {
            const before = self.committed;
            if (!try self.ensure(count)) return false;
            @memset(self.items[before..self.committed], fill);
            return true;
        }

        pub fn deinit(self: *Self) void {
            if (self.items.len == 0) return;
            const base: [*]align(std.heap.page_size_min) u8 = @ptrCast(@alignCast(self.items.ptr));
            const bytes = std.mem.alignForward(usize, self.items.len * @sizeOf(T), std.heap.pageSize());
            if (is_windows) {
                _ = win32.VirtualFree(@ptrCast(base), 0, win32.MEM_RELEASE);
            } else {
                std.posix.munmap(base[0..bytes]);
            }
            self.* = .{};
        }
    };
}

test "a region grows in place and reports its reservation" {
    var r = try Region(u64).reserve(1 << 20);
    defer r.deinit();
    const base = r.items.ptr;
    try std.testing.expect(try r.ensure(10));
    r.items[9] = 7;
    try std.testing.expect(try r.ensure(100_000));
    r.items[99_999] = 9;
    try std.testing.expectEqual(base, r.items.ptr);
    try std.testing.expectEqual(@as(u64, 7), r.items[9]);
    try std.testing.expect(!try r.ensure((1 << 20) + 1));
}
