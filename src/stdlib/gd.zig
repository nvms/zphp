const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cInclude("gd.h");
    @cInclude("gdfontt.h");
    @cInclude("gdfonts.h");
    @cInclude("gdfontmb.h");
    @cInclude("gdfontl.h");
    @cInclude("gdfontg.h");
    @cInclude("stdio.h");
    @cInclude("unistd.h");
});

// PHP's GD functions return/accept a GdImage object whose underlying state is
// a gdImagePtr (a C pointer). zphp wraps it in a PhpObject with __gd_ptr.

fn getImg(obj: *const PhpObject) ?*c.gdImageStruct {
    const v = obj.get("__gd_ptr");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn wrapImg(ctx: *NativeContext, im: ?*c.gdImageStruct) !Value {
    if (im == null) return .{ .bool = false };
    const obj = try ctx.createObject("GdImage");
    try obj.set(ctx.allocator, "__gd_ptr", .{ .int = @intCast(@intFromPtr(im.?)) });
    return .{ .object = obj };
}

fn dupZ(ctx: *NativeContext, s: []const u8) ![:0]u8 {
    const z = try ctx.allocator.alloc(u8, s.len + 1);
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    try ctx.strings.append(ctx.allocator, z);
    return z[0..s.len :0];
}

fn dupString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const owned = try ctx.allocator.dupe(u8, s);
    try ctx.strings.append(ctx.allocator, owned);
    return owned;
}

fn argInt(args: []const Value, idx: usize) ?i64 {
    if (args.len <= idx) return null;
    return switch (args[idx]) {
        .int => |i| i,
        .float => |f| @intFromFloat(f),
        .bool => |b| if (b) @as(i64, 1) else @as(i64, 0),
        else => null,
    };
}

fn argFloat(args: []const Value, idx: usize) ?f64 {
    if (args.len <= idx) return null;
    return switch (args[idx]) {
        .float => |f| f,
        .int => |i| @floatFromInt(i),
        else => null,
    };
}

fn argImg(args: []const Value, idx: usize) ?*c.gdImageStruct {
    if (args.len <= idx) return null;
    if (args[idx] != .object) return null;
    const obj = args[idx].object;
    if (!std.mem.eql(u8, obj.class_name, "GdImage")) return null;
    return getImg(obj);
}

// ---------------- create / destroy ----------------

fn imgCreate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const w = argInt(args, 0) orelse return .{ .bool = false };
    const h = argInt(args, 1) orelse return .{ .bool = false };
    const im = c.gdImageCreate(@intCast(w), @intCast(h));
    return wrapImg(ctx, im);
}

fn imgCreateTrueColor(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const w = argInt(args, 0) orelse return .{ .bool = false };
    const h = argInt(args, 1) orelse return .{ .bool = false };
    const im = c.gdImageCreateTrueColor(@intCast(w), @intCast(h));
    return wrapImg(ctx, im);
}

fn imgDestroy(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = ctx;
    const im = argImg(args, 0) orelse return .{ .bool = false };
    c.gdImageDestroy(im);
    if (args[0] == .object) {
        // zero the pointer so later operations no-op
        args[0].object.set(std.heap.page_allocator, "__gd_ptr", .{ .int = 0 }) catch {};
    }
    return .{ .bool = true };
}

fn imgCreateFromPng(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const path_z = try dupZ(ctx, args[0].string);
    const f = c.fopen(path_z.ptr, "rb") orelse return .{ .bool = false };
    defer _ = c.fclose(f);
    const im = c.gdImageCreateFromPng(f);
    return wrapImg(ctx, im);
}

fn imgCreateFromJpeg(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const path_z = try dupZ(ctx, args[0].string);
    const f = c.fopen(path_z.ptr, "rb") orelse return .{ .bool = false };
    defer _ = c.fclose(f);
    const im = c.gdImageCreateFromJpeg(f);
    return wrapImg(ctx, im);
}

fn imgCreateFromGif(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const path_z = try dupZ(ctx, args[0].string);
    const f = c.fopen(path_z.ptr, "rb") orelse return .{ .bool = false };
    defer _ = c.fclose(f);
    const im = c.gdImageCreateFromGif(f);
    return wrapImg(ctx, im);
}

fn imgCreateFromString(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const data = args[0].string;
    // try PNG first, then JPEG, then GIF (sniffed from header)
    if (data.len >= 8 and data[0] == 0x89 and data[1] == 'P' and data[2] == 'N' and data[3] == 'G') {
        const im = c.gdImageCreateFromPngPtr(@intCast(data.len), @constCast(@ptrCast(data.ptr)));
        return wrapImg(ctx, im);
    }
    if (data.len >= 3 and data[0] == 0xff and data[1] == 0xd8 and data[2] == 0xff) {
        const im = c.gdImageCreateFromJpegPtr(@intCast(data.len), @constCast(@ptrCast(data.ptr)));
        return wrapImg(ctx, im);
    }
    if (data.len >= 6 and std.mem.eql(u8, data[0..6], "GIF89a") or (data.len >= 6 and std.mem.eql(u8, data[0..6], "GIF87a"))) {
        const im = c.gdImageCreateFromGifPtr(@intCast(data.len), @constCast(@ptrCast(data.ptr)));
        return wrapImg(ctx, im);
    }
    return .{ .bool = false };
}

// ---------------- output ----------------

fn writeImageTo(ctx: *NativeContext, im: *c.gdImageStruct, args: []const Value, kind: enum { png, jpeg, gif }, quality: c_int) !Value {
    if (args.len > 1 and args[1] == .string) {
        const path_z = try dupZ(ctx, args[1].string);
        const f = c.fopen(path_z.ptr, "wb") orelse return .{ .bool = false };
        defer _ = c.fclose(f);
        switch (kind) {
            .png => c.gdImagePng(im, f),
            .jpeg => c.gdImageJpeg(im, f, quality),
            .gif => c.gdImageGif(im, f),
        }
        return .{ .bool = true };
    }
    var size: c_int = 0;
    const buf = switch (kind) {
        .png => c.gdImagePngPtr(im, &size),
        .jpeg => c.gdImageJpegPtr(im, &size, quality),
        .gif => c.gdImageGifPtr(im, &size),
    };
    if (buf == null) return .{ .bool = false };
    defer c.gdFree(buf);
    // when filename is null, PHP writes to the script's output channel - which
    // goes through ob_start buffers, not directly to stdout. append to vm.output
    // so output handlers + ob capture work correctly
    const slice_ptr: [*]const u8 = @ptrCast(buf);
    const usize_sz: usize = @intCast(size);
    try ctx.vm.output.appendSlice(ctx.allocator, slice_ptr[0..usize_sz]);
    return .{ .bool = true };
}

fn imgPng(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    return writeImageTo(ctx, im, args, .png, 0);
}

fn imgJpeg(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const q: c_int = if (args.len > 2 and args[2] == .int) @intCast(args[2].int) else 75;
    return writeImageTo(ctx, im, args, .jpeg, q);
}

fn imgGif(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    return writeImageTo(ctx, im, args, .gif, 0);
}

// ---------------- colors ----------------

fn imgColorAllocate(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const r = argInt(args, 1) orelse return .{ .bool = false };
    const g = argInt(args, 2) orelse return .{ .bool = false };
    const b = argInt(args, 3) orelse return .{ .bool = false };
    return .{ .int = @intCast(c.gdImageColorAllocate(im, @intCast(r), @intCast(g), @intCast(b))) };
}

fn imgColorAllocateAlpha(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const r = argInt(args, 1) orelse return .{ .bool = false };
    const g = argInt(args, 2) orelse return .{ .bool = false };
    const b = argInt(args, 3) orelse return .{ .bool = false };
    const al = argInt(args, 4) orelse return .{ .bool = false };
    return .{ .int = @intCast(c.gdImageColorAllocateAlpha(im, @intCast(r), @intCast(g), @intCast(b), @intCast(al))) };
}

fn imgColorAt(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const x = argInt(args, 1) orelse return .{ .bool = false };
    const y = argInt(args, 2) orelse return .{ .bool = false };
    return .{ .int = @intCast(c.gdImageGetPixel(im, @intCast(x), @intCast(y))) };
}

fn imgRotate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const angle = argFloat(args, 1) orelse return .{ .bool = false };
    const bg_color = argInt(args, 2) orelse 0;
    const out = c.gdImageRotateInterpolated(im, @floatCast(angle), @intCast(bg_color));
    return wrapImg(ctx, out);
}

fn imgColorTransparent(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .int = -1 };
    if (args.len >= 2 and args[1] == .int) {
        c.gdImageColorTransparent(im, @intCast(args[1].int));
    }
    return .{ .int = @intCast(im.*.transparent) };
}

fn imgColorsForIndex(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const idx = argInt(args, 1) orelse return .{ .bool = false };
    var r: c_int = 0;
    var g: c_int = 0;
    var b: c_int = 0;
    var alpha: c_int = 0;
    if (im.*.trueColor != 0) {
        const ci: c_int = @intCast(idx);
        r = (ci >> 16) & 0xff;
        g = (ci >> 8) & 0xff;
        b = ci & 0xff;
        alpha = (ci >> 24) & 0x7f;
    } else {
        const ci: usize = @intCast(idx);
        if (ci >= im.*.colorsTotal) return .{ .bool = false };
        r = im.*.red[ci];
        g = im.*.green[ci];
        b = im.*.blue[ci];
        alpha = im.*.alpha[ci];
    }
    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .string = "red" }, .{ .int = r });
    try arr.set(ctx.allocator, .{ .string = "green" }, .{ .int = g });
    try arr.set(ctx.allocator, .{ .string = "blue" }, .{ .int = b });
    try arr.set(ctx.allocator, .{ .string = "alpha" }, .{ .int = alpha });
    return .{ .array = arr };
}

// ---------------- drawing ----------------

fn imgSetPixel(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const x = argInt(args, 1) orelse return .{ .bool = false };
    const y = argInt(args, 2) orelse return .{ .bool = false };
    const col = argInt(args, 3) orelse return .{ .bool = false };
    c.gdImageSetPixel(im, @intCast(x), @intCast(y), @intCast(col));
    return .{ .bool = true };
}

fn imgLine(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const x1 = argInt(args, 1) orelse return .{ .bool = false };
    const y1 = argInt(args, 2) orelse return .{ .bool = false };
    const x2 = argInt(args, 3) orelse return .{ .bool = false };
    const y2 = argInt(args, 4) orelse return .{ .bool = false };
    const col = argInt(args, 5) orelse return .{ .bool = false };
    c.gdImageLine(im, @intCast(x1), @intCast(y1), @intCast(x2), @intCast(y2), @intCast(col));
    return .{ .bool = true };
}

fn imgRectangle(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const x1 = argInt(args, 1) orelse return .{ .bool = false };
    const y1 = argInt(args, 2) orelse return .{ .bool = false };
    const x2 = argInt(args, 3) orelse return .{ .bool = false };
    const y2 = argInt(args, 4) orelse return .{ .bool = false };
    const col = argInt(args, 5) orelse return .{ .bool = false };
    c.gdImageRectangle(im, @intCast(x1), @intCast(y1), @intCast(x2), @intCast(y2), @intCast(col));
    return .{ .bool = true };
}

fn imgFilledRectangle(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const x1 = argInt(args, 1) orelse return .{ .bool = false };
    const y1 = argInt(args, 2) orelse return .{ .bool = false };
    const x2 = argInt(args, 3) orelse return .{ .bool = false };
    const y2 = argInt(args, 4) orelse return .{ .bool = false };
    const col = argInt(args, 5) orelse return .{ .bool = false };
    c.gdImageFilledRectangle(im, @intCast(x1), @intCast(y1), @intCast(x2), @intCast(y2), @intCast(col));
    return .{ .bool = true };
}

fn imgEllipse(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const cx = argInt(args, 1) orelse return .{ .bool = false };
    const cy = argInt(args, 2) orelse return .{ .bool = false };
    const w = argInt(args, 3) orelse return .{ .bool = false };
    const h = argInt(args, 4) orelse return .{ .bool = false };
    const col = argInt(args, 5) orelse return .{ .bool = false };
    c.gdImageEllipse(im, @intCast(cx), @intCast(cy), @intCast(w), @intCast(h), @intCast(col));
    return .{ .bool = true };
}

fn imgFilledEllipse(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const cx = argInt(args, 1) orelse return .{ .bool = false };
    const cy = argInt(args, 2) orelse return .{ .bool = false };
    const w = argInt(args, 3) orelse return .{ .bool = false };
    const h = argInt(args, 4) orelse return .{ .bool = false };
    const col = argInt(args, 5) orelse return .{ .bool = false };
    c.gdImageFilledEllipse(im, @intCast(cx), @intCast(cy), @intCast(w), @intCast(h), @intCast(col));
    return .{ .bool = true };
}

fn imgArc(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const cx = argInt(args, 1) orelse return .{ .bool = false };
    const cy = argInt(args, 2) orelse return .{ .bool = false };
    const w = argInt(args, 3) orelse return .{ .bool = false };
    const h = argInt(args, 4) orelse return .{ .bool = false };
    const s = argInt(args, 5) orelse return .{ .bool = false };
    const e = argInt(args, 6) orelse return .{ .bool = false };
    const col = argInt(args, 7) orelse return .{ .bool = false };
    c.gdImageArc(im, @intCast(cx), @intCast(cy), @intCast(w), @intCast(h), @intCast(s), @intCast(e), @intCast(col));
    return .{ .bool = true };
}

fn imgFill(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const x = argInt(args, 1) orelse return .{ .bool = false };
    const y = argInt(args, 2) orelse return .{ .bool = false };
    const col = argInt(args, 3) orelse return .{ .bool = false };
    c.gdImageFill(im, @intCast(x), @intCast(y), @intCast(col));
    return .{ .bool = true };
}

// ---------------- text ----------------

fn imgString(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const font = argInt(args, 1) orelse return .{ .bool = false };
    const x = argInt(args, 2) orelse return .{ .bool = false };
    const y = argInt(args, 3) orelse return .{ .bool = false };
    if (args.len < 5 or args[4] != .string) return .{ .bool = false };
    const col = argInt(args, 5) orelse return .{ .bool = false };

    const text_z = try dupZ(ctx, args[4].string);
    const gd_font = switch (font) {
        2 => c.gdFontGetSmall(),
        3 => c.gdFontGetMediumBold(),
        4 => c.gdFontGetLarge(),
        5 => c.gdFontGetGiant(),
        else => c.gdFontGetTiny(),
    };
    c.gdImageString(im, gd_font, @intCast(x), @intCast(y), @ptrCast(@constCast(text_z.ptr)), @intCast(col));
    return .{ .bool = true };
}

fn imgTtfText(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 8) return .{ .bool = false };
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const size: f64 = switch (args[1]) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => return .{ .bool = false },
    };
    const angle: f64 = switch (args[2]) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => return .{ .bool = false },
    };
    const x = argInt(args, 3) orelse return .{ .bool = false };
    const y = argInt(args, 4) orelse return .{ .bool = false };
    const col = argInt(args, 5) orelse return .{ .bool = false };
    if (args[6] != .string or args[7] != .string) return .{ .bool = false };
    const font_z = try dupZ(ctx, args[6].string);
    const text_z = try dupZ(ctx, args[7].string);

    var brect: [8]c_int = .{0} ** 8;
    const err = c.gdImageStringFT(im, &brect, @intCast(col), font_z.ptr, size, angle, @intCast(x), @intCast(y), text_z.ptr);
    if (err != null) return .{ .bool = false };
    // return the bounding box as a PHP array (8 ints)
    const arr = try ctx.createArray();
    for (brect, 0..) |v, i| try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .int = @intCast(v) });
    return .{ .array = arr };
}

// ---------------- copy ----------------

fn imgCopy(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const dst = argImg(args, 0) orelse return .{ .bool = false };
    const src = argImg(args, 1) orelse return .{ .bool = false };
    const dx = argInt(args, 2) orelse return .{ .bool = false };
    const dy = argInt(args, 3) orelse return .{ .bool = false };
    const sx = argInt(args, 4) orelse return .{ .bool = false };
    const sy = argInt(args, 5) orelse return .{ .bool = false };
    const w = argInt(args, 6) orelse return .{ .bool = false };
    const h = argInt(args, 7) orelse return .{ .bool = false };
    c.gdImageCopy(dst, src, @intCast(dx), @intCast(dy), @intCast(sx), @intCast(sy), @intCast(w), @intCast(h));
    return .{ .bool = true };
}

fn imgCopyResampled(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const dst = argImg(args, 0) orelse return .{ .bool = false };
    const src = argImg(args, 1) orelse return .{ .bool = false };
    const dx = argInt(args, 2) orelse return .{ .bool = false };
    const dy = argInt(args, 3) orelse return .{ .bool = false };
    const sx = argInt(args, 4) orelse return .{ .bool = false };
    const sy = argInt(args, 5) orelse return .{ .bool = false };
    const dw = argInt(args, 6) orelse return .{ .bool = false };
    const dh = argInt(args, 7) orelse return .{ .bool = false };
    const sw = argInt(args, 8) orelse return .{ .bool = false };
    const sh = argInt(args, 9) orelse return .{ .bool = false };
    c.gdImageCopyResampled(dst, src, @intCast(dx), @intCast(dy), @intCast(sx), @intCast(sy), @intCast(dw), @intCast(dh), @intCast(sw), @intCast(sh));
    return .{ .bool = true };
}

fn imgCopyResized(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const dst = argImg(args, 0) orelse return .{ .bool = false };
    const src = argImg(args, 1) orelse return .{ .bool = false };
    const dx = argInt(args, 2) orelse return .{ .bool = false };
    const dy = argInt(args, 3) orelse return .{ .bool = false };
    const sx = argInt(args, 4) orelse return .{ .bool = false };
    const sy = argInt(args, 5) orelse return .{ .bool = false };
    const dw = argInt(args, 6) orelse return .{ .bool = false };
    const dh = argInt(args, 7) orelse return .{ .bool = false };
    const sw = argInt(args, 8) orelse return .{ .bool = false };
    const sh = argInt(args, 9) orelse return .{ .bool = false };
    c.gdImageCopyResized(dst, src, @intCast(dx), @intCast(dy), @intCast(sx), @intCast(sy), @intCast(dw), @intCast(dh), @intCast(sw), @intCast(sh));
    return .{ .bool = true };
}

// ---------------- dimensions ----------------

fn imgSx(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    return .{ .int = @intCast(im.sx) };
}

fn imgSy(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    return .{ .int = @intCast(im.sy) };
}

// ---------------- alpha / interlace ----------------

fn imgAlphaBlending(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const on = argInt(args, 1) orelse return .{ .bool = false };
    c.gdImageAlphaBlending(im, @intCast(on));
    return .{ .bool = true };
}

fn imgSaveAlpha(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const on = argInt(args, 1) orelse return .{ .bool = false };
    c.gdImageSaveAlpha(im, @intCast(on));
    return .{ .bool = true };
}

fn imgInterlace(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const im = argImg(args, 0) orelse return .{ .bool = false };
    const on = argInt(args, 1) orelse return .{ .bool = false };
    c.gdImageInterlace(im, @intCast(on));
    return .{ .bool = true };
}

// ---------------- info ----------------

fn imgGetSize(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const path_z = try dupZ(ctx, args[0].string);
    // sniff via fopen + gd helpers (minimal: just open file and check magic, then return dims via libgd)
    const f = c.fopen(path_z.ptr, "rb") orelse return .{ .bool = false };
    defer _ = c.fclose(f);
    var header: [12]u8 = undefined;
    const read = c.fread(&header, 1, header.len, f);
    if (read < 4) return .{ .bool = false };
    _ = c.fseek(f, 0, c.SEEK_SET);

    var im: ?*c.gdImageStruct = null;
    var mime: []const u8 = "";
    var typ: i64 = 0;

    if (read >= 4 and header[0] == 0x89 and header[1] == 'P' and header[2] == 'N' and header[3] == 'G') {
        im = c.gdImageCreateFromPng(f);
        mime = "image/png";
        typ = 3;
    } else if (read >= 3 and header[0] == 0xff and header[1] == 0xd8 and header[2] == 0xff) {
        im = c.gdImageCreateFromJpeg(f);
        mime = "image/jpeg";
        typ = 2;
    } else if (read >= 6 and (std.mem.eql(u8, header[0..6], "GIF89a") or std.mem.eql(u8, header[0..6], "GIF87a"))) {
        im = c.gdImageCreateFromGif(f);
        mime = "image/gif";
        typ = 1;
    } else return .{ .bool = false };

    if (im == null) return .{ .bool = false };
    defer c.gdImageDestroy(im);

    const arr = try ctx.createArray();
    try arr.set(ctx.allocator, .{ .int = 0 }, .{ .int = @intCast(im.?.sx) });
    try arr.set(ctx.allocator, .{ .int = 1 }, .{ .int = @intCast(im.?.sy) });
    try arr.set(ctx.allocator, .{ .int = 2 }, .{ .int = typ });
    try arr.set(ctx.allocator, .{ .int = 3 }, .{ .string = try dupString(ctx, "") });
    try arr.set(ctx.allocator, .{ .string = try dupString(ctx, "mime") }, .{ .string = try dupString(ctx, mime) });
    try arr.set(ctx.allocator, .{ .string = try dupString(ctx, "bits") }, .{ .int = 8 });
    return .{ .array = arr };
}

// ---------------- registration ----------------

pub const entries = .{
    .{ "imagecreate", imgCreate },
    .{ "imagecreatetruecolor", imgCreateTrueColor },
    .{ "imagedestroy", imgDestroy },
    .{ "imagecreatefrompng", imgCreateFromPng },
    .{ "imagecreatefromjpeg", imgCreateFromJpeg },
    .{ "imagecreatefromgif", imgCreateFromGif },
    .{ "imagecreatefromstring", imgCreateFromString },
    .{ "imagepng", imgPng },
    .{ "imagejpeg", imgJpeg },
    .{ "imagegif", imgGif },
    .{ "imagecolorallocate", imgColorAllocate },
    .{ "imagecolorallocatealpha", imgColorAllocateAlpha },
    .{ "imagecolorat", imgColorAt },
    .{ "imagecolorsforindex", imgColorsForIndex },
    .{ "imagecolortransparent", imgColorTransparent },
    .{ "imagerotate", imgRotate },
    .{ "imagesetpixel", imgSetPixel },
    .{ "imageline", imgLine },
    .{ "imagerectangle", imgRectangle },
    .{ "imagefilledrectangle", imgFilledRectangle },
    .{ "imageellipse", imgEllipse },
    .{ "imagefilledellipse", imgFilledEllipse },
    .{ "imagearc", imgArc },
    .{ "imagefill", imgFill },
    .{ "imagestring", imgString },
    .{ "imagettftext", imgTtfText },
    .{ "imagecopy", imgCopy },
    .{ "imagecopyresampled", imgCopyResampled },
    .{ "imagecopyresized", imgCopyResized },
    .{ "imagesx", imgSx },
    .{ "imagesy", imgSy },
    .{ "imagealphablending", imgAlphaBlending },
    .{ "imagesavealpha", imgSaveAlpha },
    .{ "imageinterlace", imgInterlace },
    .{ "getimagesize", imgGetSize },
};

pub fn register(vm: *VM, a: Allocator) !void {
    const def = ClassDef{ .name = "GdImage" };
    try vm.classes.put(a, "GdImage", def);

    // font size constants
    try vm.php_constants.put(a, "IMG_PNG", .{ .int = 3 });
    try vm.php_constants.put(a, "IMG_JPG", .{ .int = 2 });
    try vm.php_constants.put(a, "IMG_JPEG", .{ .int = 2 });
    try vm.php_constants.put(a, "IMG_GIF", .{ .int = 1 });
    try vm.php_constants.put(a, "IMG_WEBP", .{ .int = 32 });
    try vm.php_constants.put(a, "IMG_BMP", .{ .int = 64 });
    try vm.php_constants.put(a, "IMG_COLOR_TILED", .{ .int = -5 });
    try vm.php_constants.put(a, "IMG_COLOR_STYLED", .{ .int = -2 });
    try vm.php_constants.put(a, "IMG_COLOR_BRUSHED", .{ .int = -3 });
    try vm.php_constants.put(a, "IMG_COLOR_TRANSPARENT", .{ .int = -6 });
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (!std.mem.eql(u8, obj.class_name, "GdImage")) continue;
        if (getImg(obj)) |im| c.gdImageDestroy(im);
    }
}
