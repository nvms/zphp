const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const StringPool = @This();

backing: Allocator,
free_lists: [9][32]?[*]u8 = @splat(@splat(null)),
counts: [9]usize = @splat(0),

fn sizeClass(length: usize, alignment: Alignment) ?usize {
    if (length > 4096 or alignment.toByteUnits() > 16) return null;
    var index: usize = 0;
    while ((@as(usize, 16) << @intCast(index)) < length) : (index += 1) {}
    return index;
}

fn capacity(index: usize) usize {
    return @as(usize, 16) << @intCast(index);
}

pub fn allocator(self: *StringPool) Allocator {
    return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
}

pub fn deinit(self: *StringPool) void {
    for (&self.counts, 0..) |*count, index| {
        for (self.free_lists[index][0..count.*]) |ptr| {
            self.backing.rawFree(ptr.?[0..capacity(index)], .@"16", @returnAddress());
        }
        count.* = 0;
    }
}

fn alloc(ctx: *anyopaque, length: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    const self: *StringPool = @ptrCast(@alignCast(ctx));
    const index = sizeClass(length, alignment) orelse return self.backing.rawAlloc(length, alignment, ra);
    if (self.counts[index] > 0) {
        self.counts[index] -= 1;
        return self.free_lists[index][self.counts[index]];
    }
    return self.backing.rawAlloc(capacity(index), .@"16", ra);
}

fn resize(ctx: *anyopaque, bytes: []u8, alignment: Alignment, length: usize, ra: usize) bool {
    const self: *StringPool = @ptrCast(@alignCast(ctx));
    const old = sizeClass(bytes.len, alignment);
    const new = sizeClass(length, alignment);
    if (old != null or new != null) return old == new;
    return self.backing.rawResize(bytes, alignment, length, ra);
}

fn remap(ctx: *anyopaque, bytes: []u8, alignment: Alignment, length: usize, ra: usize) ?[*]u8 {
    return if (resize(ctx, bytes, alignment, length, ra)) bytes.ptr else null;
}

fn free(ctx: *anyopaque, bytes: []u8, alignment: Alignment, ra: usize) void {
    const self: *StringPool = @ptrCast(@alignCast(ctx));
    const index = sizeClass(bytes.len, alignment) orelse {
        self.backing.rawFree(bytes, alignment, ra);
        return;
    };
    if (self.counts[index] < self.free_lists[index].len) {
        self.free_lists[index][self.counts[index]] = bytes.ptr;
        self.counts[index] += 1;
    } else self.backing.rawFree(bytes.ptr[0..capacity(index)], .@"16", ra);
}

test "string pool reuses bounded blocks and preserves realloc contents" {
    var pool: StringPool = .{ .backing = std.testing.allocator };
    defer pool.deinit();
    const alloc_api = pool.allocator();
    var bytes = try alloc_api.dupe(u8, "retained value");
    bytes = try alloc_api.realloc(bytes, 100);
    try std.testing.expectEqualStrings("retained value", bytes[0..14]);
    alloc_api.free(bytes);
    var blocks: [100][]u8 = undefined;
    for (&blocks) |*block| block.* = try alloc_api.alloc(u8, 4096);
    for (blocks) |block| alloc_api.free(block);
    try std.testing.expectEqual(@as(usize, 32), pool.counts[8]);
}
