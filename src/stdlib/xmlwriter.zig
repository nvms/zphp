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
    @cInclude("libxml/xmlwriter.h");
    @cInclude("libxml/tree.h");
});

fn dupString(ctx: *NativeContext, s: []const u8) ![]const u8 {
    const owned = try ctx.allocator.dupe(u8, s);
    try ctx.strings.append(ctx.allocator, owned);
    return owned;
}

fn dupZ(ctx: *NativeContext, s: []const u8) ![:0]u8 {
    const z = try ctx.allocator.alloc(u8, s.len + 1);
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    try ctx.strings.append(ctx.allocator, z);
    return z[0..s.len :0];
}

fn cstrLen(p: [*c]const u8) usize {
    return std.mem.len(p);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getWriter(obj: *const PhpObject) ?*c.xmlTextWriter {
    const v = obj.get("__writer");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn getBuffer(obj: *const PhpObject) ?*c.xmlBuffer {
    const v = obj.get("__buffer");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn closeExisting(obj: *PhpObject) void {
    if (getWriter(obj)) |w| c.xmlFreeTextWriter(w);
    if (getBuffer(obj)) |b| c.xmlBufferFree(b);
}

// ---------------- methods ----------------

fn xwOpenMemory(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    // if called statically, create object. if instance method, set up on $this
    const obj = getThis(ctx) orelse blk: {
        const o = try ctx.createObject("XMLWriter");
        break :blk o;
    };
    closeExisting(obj);
    const buf = c.xmlBufferCreate() orelse return .{ .bool = false };
    const writer = c.xmlNewTextWriterMemory(buf, 0);
    if (writer == null) {
        c.xmlBufferFree(buf);
        return .{ .bool = false };
    }
    try obj.set(ctx.allocator, "__buffer", .{ .int = @intCast(@intFromPtr(buf)) });
    try obj.set(ctx.allocator, "__writer", .{ .int = @intCast(@intFromPtr(writer)) });
    if (getThis(ctx) == null) return .{ .object = obj };
    return .{ .bool = true };
}

fn xwOpenURI(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse blk: {
        const o = try ctx.createObject("XMLWriter");
        break :blk o;
    };
    closeExisting(obj);
    const path_z = try dupZ(ctx, args[0].string);
    const writer = c.xmlNewTextWriterFilename(path_z.ptr, 0);
    if (writer == null) return .{ .bool = false };
    try obj.set(ctx.allocator, "__writer", .{ .int = @intCast(@intFromPtr(writer)) });
    if (getThis(ctx) == null) return .{ .object = obj };
    return .{ .bool = true };
}

fn xwToMemory(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = try ctx.createObject("XMLWriter");
    const buf = c.xmlBufferCreate() orelse return .{ .bool = false };
    const writer = c.xmlNewTextWriterMemory(buf, 0);
    if (writer == null) {
        c.xmlBufferFree(buf);
        return .{ .bool = false };
    }
    try obj.set(ctx.allocator, "__buffer", .{ .int = @intCast(@intFromPtr(buf)) });
    try obj.set(ctx.allocator, "__writer", .{ .int = @intCast(@intFromPtr(writer)) });
    return .{ .object = obj };
}

fn xwToUri(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = try ctx.createObject("XMLWriter");
    const path_z = try dupZ(ctx, args[0].string);
    const writer = c.xmlNewTextWriterFilename(path_z.ptr, 0);
    if (writer == null) return .{ .bool = false };
    try obj.set(ctx.allocator, "__writer", .{ .int = @intCast(@intFromPtr(writer)) });
    return .{ .object = obj };
}

fn xwOutputMemory(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = try dupString(ctx, "") };
    const writer = getWriter(obj) orelse return .{ .string = try dupString(ctx, "") };
    var flush = true;
    if (args.len > 0 and args[0] == .bool) flush = args[0].bool;
    if (flush) _ = c.xmlTextWriterFlush(writer);
    const buf = getBuffer(obj) orelse return .{ .string = try dupString(ctx, "") };
    const content = c.xmlBufferContent(buf);
    if (content == null) return .{ .string = try dupString(ctx, "") };
    const slice = content[0..cstrLen(content)];
    const out = try dupString(ctx, slice);
    if (flush) c.xmlBufferEmpty(buf);
    return .{ .string = out };
}

fn xwFlush(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const writer = getWriter(obj) orelse return .{ .int = 0 };
    var empty = true;
    if (args.len > 0 and args[0] == .bool) empty = args[0].bool;
    const rc = c.xmlTextWriterFlush(writer);
    // for memory writers, PHP returns the buffer contents string when emptying
    if (getBuffer(obj)) |buf| {
        const content = c.xmlBufferContent(buf);
        if (content == null) return .{ .string = try dupString(ctx, "") };
        const slice = content[0..cstrLen(content)];
        const out = try dupString(ctx, slice);
        if (empty) c.xmlBufferEmpty(buf);
        return .{ .string = out };
    }
    return .{ .int = @intCast(rc) };
}

fn xwSetIndent(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .bool) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const rc = c.xmlTextWriterSetIndent(writer, if (args[0].bool) 1 else 0);
    return .{ .bool = rc >= 0 };
}

fn xwSetIndentString(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const s_z = try dupZ(ctx, args[0].string);
    const rc = c.xmlTextWriterSetIndentString(writer, @ptrCast(s_z.ptr));
    return .{ .bool = rc >= 0 };
}

fn xwStartDocument(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const ver_z: ?[:0]u8 = if (args.len > 0 and args[0] == .string) try dupZ(ctx, args[0].string) else null;
    const enc_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string and args[1].string.len > 0) try dupZ(ctx, args[1].string) else null;
    const sta_z: ?[:0]u8 = if (args.len > 2 and args[2] == .string and args[2].string.len > 0) try dupZ(ctx, args[2].string) else null;
    const ver_ptr: [*c]const u8 = if (ver_z) |z| @ptrCast(z.ptr) else null;
    const enc_ptr: [*c]const u8 = if (enc_z) |z| @ptrCast(z.ptr) else null;
    const sta_ptr: [*c]const u8 = if (sta_z) |z| @ptrCast(z.ptr) else null;
    const rc = c.xmlTextWriterStartDocument(writer, ver_ptr, enc_ptr, sta_ptr);
    return .{ .bool = rc >= 0 };
}

fn xwEndDocument(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    return .{ .bool = c.xmlTextWriterEndDocument(writer) >= 0 };
}

fn xwStartElement(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const z = try dupZ(ctx, args[0].string);
    return .{ .bool = c.xmlTextWriterStartElement(writer, @ptrCast(z.ptr)) >= 0 };
}

fn xwStartElementNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const prefix_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.len > 0)
        @ptrCast((try dupZ(ctx, args[0].string)).ptr)
    else
        null;
    if (args[1] != .string) return .{ .bool = false };
    const name_z = try dupZ(ctx, args[1].string);
    const ns_ptr: [*c]const u8 = if (args[2] == .string and args[2].string.len > 0)
        @ptrCast((try dupZ(ctx, args[2].string)).ptr)
    else
        null;
    return .{ .bool = c.xmlTextWriterStartElementNS(writer, prefix_ptr, @ptrCast(name_z.ptr), ns_ptr) >= 0 };
}

fn xwEndElement(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    return .{ .bool = c.xmlTextWriterEndElement(writer) >= 0 };
}

fn xwFullEndElement(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    return .{ .bool = c.xmlTextWriterFullEndElement(writer) >= 0 };
}

fn xwWriteElement(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const name_z = try dupZ(ctx, args[0].string);
    const content_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string) try dupZ(ctx, args[1].string) else null;
    const content_ptr: [*c]const u8 = if (content_z) |z| @ptrCast(z.ptr) else null;
    return .{ .bool = c.xmlTextWriterWriteElement(writer, @ptrCast(name_z.ptr), content_ptr) >= 0 };
}

fn xwWriteAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const name_z = try dupZ(ctx, args[0].string);
    const val_z = try dupZ(ctx, args[1].string);
    return .{ .bool = c.xmlTextWriterWriteAttribute(writer, @ptrCast(name_z.ptr), @ptrCast(val_z.ptr)) >= 0 };
}

fn xwWriteAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 4) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const prefix_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.len > 0)
        @ptrCast((try dupZ(ctx, args[0].string)).ptr)
    else
        null;
    if (args[1] != .string or args[3] != .string) return .{ .bool = false };
    const name_z = try dupZ(ctx, args[1].string);
    const ns_ptr: [*c]const u8 = if (args[2] == .string and args[2].string.len > 0)
        @ptrCast((try dupZ(ctx, args[2].string)).ptr)
    else
        null;
    const val_z = try dupZ(ctx, args[3].string);
    return .{ .bool = c.xmlTextWriterWriteAttributeNS(writer, prefix_ptr, @ptrCast(name_z.ptr), ns_ptr, @ptrCast(val_z.ptr)) >= 0 };
}

fn xwStartAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const z = try dupZ(ctx, args[0].string);
    return .{ .bool = c.xmlTextWriterStartAttribute(writer, @ptrCast(z.ptr)) >= 0 };
}

fn xwEndAttribute(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    return .{ .bool = c.xmlTextWriterEndAttribute(writer) >= 0 };
}

fn xwText(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const z = try dupZ(ctx, args[0].string);
    return .{ .bool = c.xmlTextWriterWriteString(writer, @ptrCast(z.ptr)) >= 0 };
}

fn xwWriteRaw(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const z = try dupZ(ctx, args[0].string);
    return .{ .bool = c.xmlTextWriterWriteRaw(writer, @ptrCast(z.ptr)) >= 0 };
}

fn xwWriteCData(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const z = try dupZ(ctx, args[0].string);
    return .{ .bool = c.xmlTextWriterWriteCDATA(writer, @ptrCast(z.ptr)) >= 0 };
}

fn xwStartCdata(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    return .{ .bool = c.xmlTextWriterStartCDATA(writer) >= 0 };
}

fn xwEndCdata(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    return .{ .bool = c.xmlTextWriterEndCDATA(writer) >= 0 };
}

fn xwWriteComment(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const z = try dupZ(ctx, args[0].string);
    return .{ .bool = c.xmlTextWriterWriteComment(writer, @ptrCast(z.ptr)) >= 0 };
}

fn xwStartComment(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    return .{ .bool = c.xmlTextWriterStartComment(writer) >= 0 };
}

fn xwEndComment(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    return .{ .bool = c.xmlTextWriterEndComment(writer) >= 0 };
}

fn xwWritePi(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const writer = getWriter(obj) orelse return .{ .bool = false };
    const t_z = try dupZ(ctx, args[0].string);
    const c_z = try dupZ(ctx, args[1].string);
    return .{ .bool = c.xmlTextWriterWritePI(writer, @ptrCast(t_z.ptr), @ptrCast(c_z.ptr)) >= 0 };
}

// ---------------- registration ----------------

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "XMLWriter" };

    inline for (.{
        "openMemory", "openURI", "outputMemory", "flush",
        "setIndent", "setIndentString",
        "startDocument", "endDocument",
        "startElement", "startElementNS", "endElement", "fullEndElement",
        "writeElement",
        "writeAttribute", "writeAttributeNS", "startAttribute", "endAttribute",
        "text", "writeRaw",
        "writeCData", "startCdata", "endCdata",
        "writeComment", "startComment", "endComment",
        "writePi",
        "toMemory", "toUri",
    }) |m| {
        try def.methods.put(a, m, .{ .name = m, .arity = 0 });
    }
    try vm.classes.put(a, "XMLWriter", def);

    try vm.native_fns.put(a, "XMLWriter::openMemory", xwOpenMemory);
    try vm.native_fns.put(a, "XMLWriter::openURI", xwOpenURI);
    try vm.native_fns.put(a, "XMLWriter::outputMemory", xwOutputMemory);
    try vm.native_fns.put(a, "XMLWriter::flush", xwFlush);
    try vm.native_fns.put(a, "XMLWriter::setIndent", xwSetIndent);
    try vm.native_fns.put(a, "XMLWriter::setIndentString", xwSetIndentString);
    try vm.native_fns.put(a, "XMLWriter::startDocument", xwStartDocument);
    try vm.native_fns.put(a, "XMLWriter::endDocument", xwEndDocument);
    try vm.native_fns.put(a, "XMLWriter::startElement", xwStartElement);
    try vm.native_fns.put(a, "XMLWriter::startElementNS", xwStartElementNS);
    try vm.native_fns.put(a, "XMLWriter::endElement", xwEndElement);
    try vm.native_fns.put(a, "XMLWriter::fullEndElement", xwFullEndElement);
    try vm.native_fns.put(a, "XMLWriter::writeElement", xwWriteElement);
    try vm.native_fns.put(a, "XMLWriter::writeAttribute", xwWriteAttribute);
    try vm.native_fns.put(a, "XMLWriter::writeAttributeNS", xwWriteAttributeNS);
    try vm.native_fns.put(a, "XMLWriter::startAttribute", xwStartAttribute);
    try vm.native_fns.put(a, "XMLWriter::endAttribute", xwEndAttribute);
    try vm.native_fns.put(a, "XMLWriter::text", xwText);
    try vm.native_fns.put(a, "XMLWriter::writeRaw", xwWriteRaw);
    try vm.native_fns.put(a, "XMLWriter::writeCData", xwWriteCData);
    try vm.native_fns.put(a, "XMLWriter::startCdata", xwStartCdata);
    try vm.native_fns.put(a, "XMLWriter::endCdata", xwEndCdata);
    try vm.native_fns.put(a, "XMLWriter::writeComment", xwWriteComment);
    try vm.native_fns.put(a, "XMLWriter::startComment", xwStartComment);
    try vm.native_fns.put(a, "XMLWriter::endComment", xwEndComment);
    try vm.native_fns.put(a, "XMLWriter::writePi", xwWritePi);
    try vm.native_fns.put(a, "XMLWriter::toMemory", xwToMemory);
    try vm.native_fns.put(a, "XMLWriter::toUri", xwToUri);

    // procedural API: xmlwriter_* mirrors of every method (first arg = $writer)
    // PHP exposes both styles. zphp registers them as native functions
    inline for (.{
        .{ "xmlwriter_open_memory", procOpenMemory },
        .{ "xmlwriter_open_uri", procOpenURI },
        .{ "xmlwriter_output_memory", procOutputMemory },
        .{ "xmlwriter_flush", procFlush },
        .{ "xmlwriter_set_indent", procSetIndent },
        .{ "xmlwriter_set_indent_string", procSetIndentString },
        .{ "xmlwriter_start_document", procStartDocument },
        .{ "xmlwriter_end_document", procEndDocument },
        .{ "xmlwriter_start_element", procStartElement },
        .{ "xmlwriter_start_element_ns", procStartElementNS },
        .{ "xmlwriter_end_element", procEndElement },
        .{ "xmlwriter_full_end_element", procFullEndElement },
        .{ "xmlwriter_write_element", procWriteElement },
        .{ "xmlwriter_write_attribute", procWriteAttribute },
        .{ "xmlwriter_write_attribute_ns", procWriteAttributeNS },
        .{ "xmlwriter_start_attribute", procStartAttribute },
        .{ "xmlwriter_end_attribute", procEndAttribute },
        .{ "xmlwriter_text", procText },
        .{ "xmlwriter_write_raw", procWriteRaw },
        .{ "xmlwriter_write_cdata", procWriteCData },
        .{ "xmlwriter_start_cdata", procStartCdata },
        .{ "xmlwriter_end_cdata", procEndCdata },
        .{ "xmlwriter_write_comment", procWriteComment },
        .{ "xmlwriter_start_comment", procStartComment },
        .{ "xmlwriter_end_comment", procEndComment },
        .{ "xmlwriter_write_pi", procWritePi },
    }) |pair| {
        try vm.native_fns.put(a, pair[0], pair[1]);
    }
}

// procedural wrappers: each takes $writer as first arg, forwards the rest
fn forwardOnObj(ctx: *NativeContext, args: []const Value, comptime instance_fn: anytype) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    return ctx.callMethod(args[0].object, methodNameFor(instance_fn), args[1..]);
}

// for the procedural wrappers we directly invoke the instance fn by hand-rolling
// the dispatch: copy the relevant args and present them with $this set. simplest
// path: call the instance method through callMethod which sets up the frame
fn procCall(ctx: *NativeContext, args: []const Value, comptime method: []const u8) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    return ctx.callMethod(args[0].object, method, args[1..]);
}

fn procOpenMemory(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return xwToMemory(ctx, &.{});
}
fn procOpenURI(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return xwToUri(ctx, args);
}
fn procOutputMemory(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return procCall(ctx, args, "outputMemory");
}
fn procFlush(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "flush"); }
fn procSetIndent(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "setIndent"); }
fn procSetIndentString(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "setIndentString"); }
fn procStartDocument(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "startDocument"); }
fn procEndDocument(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "endDocument"); }
fn procStartElement(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "startElement"); }
fn procStartElementNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "startElementNS"); }
fn procEndElement(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "endElement"); }
fn procFullEndElement(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "fullEndElement"); }
fn procWriteElement(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "writeElement"); }
fn procWriteAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "writeAttribute"); }
fn procWriteAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "writeAttributeNS"); }
fn procStartAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "startAttribute"); }
fn procEndAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "endAttribute"); }
fn procText(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "text"); }
fn procWriteRaw(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "writeRaw"); }
fn procWriteCData(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "writeCData"); }
fn procStartCdata(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "startCdata"); }
fn procEndCdata(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "endCdata"); }
fn procWriteComment(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "writeComment"); }
fn procStartComment(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "startComment"); }
fn procEndComment(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "endComment"); }
fn procWritePi(ctx: *NativeContext, args: []const Value) RuntimeError!Value { return procCall(ctx, args, "writePi"); }

fn methodNameFor(comptime _: anytype) []const u8 { return ""; }

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (!std.mem.eql(u8, obj.class_name, "XMLWriter")) continue;
        if (getWriter(obj)) |w| c.xmlFreeTextWriter(w);
        if (getBuffer(obj)) |b| c.xmlBufferFree(b);
    }
}
