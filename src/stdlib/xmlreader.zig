const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeHandle = @import("../runtime/value.zig").NativeHandle;
const dom = @import("dom.zig");
const vm_mod = @import("../runtime/vm.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cInclude("libxml/xmlreader.h");
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

fn getReader(obj: *const PhpObject) ?*c.xmlTextReader {
    return obj.native.get(c.xmlTextReader, .xml_reader);
}

fn setReader(obj: *PhpObject, reader: ?*c.xmlTextReader) void {
    obj.native = .{ .kind = .xml_reader, .ptr = NativeHandle.addr(reader) };
}

fn closeExisting(obj: *PhpObject) void {
    if (getReader(obj)) |r| c.xmlFreeTextReader(r);
    obj.native.ptr = 0;
}

pub fn cleanupObject(obj: *PhpObject) void {
    if (!obj.pooled and std.mem.eql(u8, obj.class_name, "XMLReader")) closeExisting(obj);
}

// ---------------- methods ----------------

fn xrOpen(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    closeExisting(obj);

    const path_z = try dupZ(ctx, args[0].string.bytes());
    const enc_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string and args[1].string.bytes().len > 0)
        try dupZ(ctx, args[1].string.bytes())
    else
        null;
    const enc_ptr: [*c]const u8 = if (enc_z) |e| @ptrCast(e.ptr) else null;
    const opts: c_int = if (args.len > 2 and args[2] == .int) @intCast(args[2].int) else 0;

    const reader = c.xmlReaderForFile(path_z.ptr, enc_ptr, opts);
    if (reader == null) return NativeResult.scalar(.{ .bool = false });
    setReader(obj, reader);
    return NativeResult.scalar(.{ .bool = true });
}

fn xrXml(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const src = args[0].string.bytes();
    const enc_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string and args[1].string.bytes().len > 0)
        try dupZ(ctx, args[1].string.bytes())
    else
        null;
    const enc_ptr: [*c]const u8 = if (enc_z) |e| @ptrCast(e.ptr) else null;
    const opts: c_int = if (args.len > 2 and args[2] == .int) @intCast(args[2].int) else 0;

    const reader = c.xmlReaderForMemory(src.ptr, @intCast(src.len), null, enc_ptr, opts);
    if (reader == null) {
        if (getThis(ctx)) |_| return NativeResult.scalar(.{ .bool = false });
        return NativeResult.scalar(.{ .bool = false });
    }

    // PHP's XMLReader::XML works both as an instance method (initializes $this and
    // returns bool) and as a static factory (creates a new XMLReader). When $this
    // is absent we synthesize a new instance
    if (getThis(ctx)) |obj| {
        closeExisting(obj);
        setReader(obj, reader);
        return NativeResult.scalar(.{ .bool = true });
    }
    const obj = try ctx.createObject("XMLReader");
    setReader(obj, reader);
    return NativeResult.borrowed(.{ .object = obj });
}

fn xrFromString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject("XMLReader");
    const src = args[0].string.bytes();
    const enc_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string and args[1].string.bytes().len > 0)
        try dupZ(ctx, args[1].string.bytes())
    else
        null;
    const enc_ptr: [*c]const u8 = if (enc_z) |e| @ptrCast(e.ptr) else null;
    const opts: c_int = if (args.len > 2 and args[2] == .int) @intCast(args[2].int) else 0;
    const reader = c.xmlReaderForMemory(src.ptr, @intCast(src.len), null, enc_ptr, opts);
    if (reader == null) return NativeResult.scalar(.{ .bool = false });
    setReader(obj, reader);
    return NativeResult.borrowed(.{ .object = obj });
}

fn xrFromUri(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = try ctx.createObject("XMLReader");
    const path_z = try dupZ(ctx, args[0].string.bytes());
    const enc_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string and args[1].string.bytes().len > 0)
        try dupZ(ctx, args[1].string.bytes())
    else
        null;
    const enc_ptr: [*c]const u8 = if (enc_z) |e| @ptrCast(e.ptr) else null;
    const opts: c_int = if (args.len > 2 and args[2] == .int) @intCast(args[2].int) else 0;
    const reader = c.xmlReaderForFile(path_z.ptr, enc_ptr, opts);
    if (reader == null) return NativeResult.scalar(.{ .bool = false });
    setReader(obj, reader);
    return NativeResult.borrowed(.{ .object = obj });
}

fn xrClose(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    closeExisting(obj);
    return NativeResult.scalar(.{ .bool = true });
}

fn xrRead(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderRead(r) == 1 });
}

fn xrNext(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len > 0 and args[0] == .string and args[0].string.bytes().len > 0) {
        const name_z = try dupZ(ctx, args[0].string.bytes());
        // walk until we hit a matching element
        while (true) {
            const rc = c.xmlTextReaderNext(r);
            if (rc != 1) return NativeResult.scalar(.{ .bool = false });
            const nt = c.xmlTextReaderNodeType(r);
            if (nt == c.XML_READER_TYPE_ELEMENT) {
                const cur = c.xmlTextReaderConstLocalName(r);
                if (cur != null and std.mem.eql(u8, cur[0..cstrLen(cur)], name_z[0..name_z.len])) {
                    return NativeResult.scalar(.{ .bool = true });
                }
            }
        }
    }
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderNext(r) == 1 });
}

fn xrMoveToAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const name_z = try dupZ(ctx, args[0].string.bytes());
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderMoveToAttribute(r, @ptrCast(name_z.ptr)) == 1 });
}

fn xrMoveToAttributeNo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderMoveToAttributeNo(r, @intCast(args[0].int)) == 1 });
}

fn xrMoveToAttributeNs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const ns_z = try dupZ(ctx, args[1].string.bytes());
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderMoveToAttributeNs(r, @ptrCast(name_z.ptr), @ptrCast(ns_z.ptr)) == 1 });
}

fn xrMoveToElement(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderMoveToElement(r) == 1 });
}

fn xrMoveToFirstAttribute(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderMoveToFirstAttribute(r) == 1 });
}

fn xrMoveToNextAttribute(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderMoveToNextAttribute(r) == 1 });
}

fn xrGetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const r = getReader(obj) orelse return NativeResult.scalar(.null);
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const v = c.xmlTextReaderGetAttribute(r, @ptrCast(name_z.ptr));
    if (v == null) return NativeResult.scalar(.null);
    defer c.xmlFree.?(v);
    return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
}

fn xrGetAttributeNo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const r = getReader(obj) orelse return NativeResult.scalar(.null);
    const v = c.xmlTextReaderGetAttributeNo(r, @intCast(args[0].int));
    if (v == null) return NativeResult.scalar(.null);
    defer c.xmlFree.?(v);
    return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
}

fn xrGetAttributeNs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const r = getReader(obj) orelse return NativeResult.scalar(.null);
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const ns_z = try dupZ(ctx, args[1].string.bytes());
    const v = c.xmlTextReaderGetAttributeNs(r, @ptrCast(name_z.ptr), @ptrCast(ns_z.ptr));
    if (v == null) return NativeResult.scalar(.null);
    defer c.xmlFree.?(v);
    return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
}

fn xrReadInnerXml(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const v = c.xmlTextReaderReadInnerXml(r);
    if (v == null) return try NativeResult.copyString(ctx.allocator, "");
    defer c.xmlFree.?(v);
    return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
}

fn xrReadOuterXml(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const v = c.xmlTextReaderReadOuterXml(r);
    if (v == null) return try NativeResult.copyString(ctx.allocator, "");
    defer c.xmlFree.?(v);
    return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
}

fn xrReadString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const v = c.xmlTextReaderReadString(r);
    if (v == null) return try NativeResult.copyString(ctx.allocator, "");
    defer c.xmlFree.?(v);
    return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
}

fn xrIsValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = c.xmlTextReaderIsValid(r) == 1 });
}

fn xrExpand(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // expand() returns a DOMNode for the current node. requires the dom module's
    // wrapping. building a DOMElement/DOMText/etc wrapper here would create a
    // node tied to an internal reader doc; PHP's documented behavior is the
    // same. We pass through to dom.wrapNode equivalent.
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const r = getReader(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const node = c.xmlTextReaderExpand(r) orelse return NativeResult.scalar(.{ .bool = false });
    // build a minimal DOMNode wrapper. dispatch class name from node type
    const cls = switch (node.*.type) {
        1 => "DOMElement", // XML_ELEMENT_NODE
        3 => "DOMText",
        4 => "DOMCdataSection",
        7 => "DOMProcessingInstruction",
        8 => "DOMComment",
        else => "DOMNode",
    };
    const dom_obj = try ctx.createObject(cls);
    dom.setNodePtr(dom_obj, @ptrCast(node));
    return NativeResult.borrowed(.{ .object = dom_obj });
}

fn xrGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const r = getReader(obj) orelse return NativeResult.scalar(.null);
    const prop = args[0].string.bytes();

    if (std.mem.eql(u8, prop, "nodeType")) {
        return NativeResult.scalar(.{ .int = @intCast(c.xmlTextReaderNodeType(r)) });
    }
    if (std.mem.eql(u8, prop, "name")) {
        const v = c.xmlTextReaderConstName(r);
        if (v == null) return try NativeResult.copyString(ctx.allocator, "");
        return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
    }
    if (std.mem.eql(u8, prop, "localName")) {
        const v = c.xmlTextReaderConstLocalName(r);
        if (v == null) return try NativeResult.copyString(ctx.allocator, "");
        return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
    }
    if (std.mem.eql(u8, prop, "prefix")) {
        const v = c.xmlTextReaderConstPrefix(r);
        if (v == null) return try NativeResult.copyString(ctx.allocator, "");
        return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
    }
    if (std.mem.eql(u8, prop, "namespaceURI")) {
        const v = c.xmlTextReaderConstNamespaceUri(r);
        if (v == null) return try NativeResult.copyString(ctx.allocator, "");
        return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
    }
    if (std.mem.eql(u8, prop, "value")) {
        const v = c.xmlTextReaderConstValue(r);
        if (v == null) return try NativeResult.copyString(ctx.allocator, "");
        return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
    }
    if (std.mem.eql(u8, prop, "baseURI")) {
        const v = c.xmlTextReaderConstBaseUri(r);
        if (v == null) return try NativeResult.copyString(ctx.allocator, "");
        return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
    }
    if (std.mem.eql(u8, prop, "xmlLang")) {
        const v = c.xmlTextReaderConstXmlLang(r);
        if (v == null) return try NativeResult.copyString(ctx.allocator, "");
        return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
    }
    if (std.mem.eql(u8, prop, "depth")) {
        return NativeResult.scalar(.{ .int = @intCast(c.xmlTextReaderDepth(r)) });
    }
    if (std.mem.eql(u8, prop, "attributeCount")) {
        return NativeResult.scalar(.{ .int = @intCast(c.xmlTextReaderAttributeCount(r)) });
    }
    if (std.mem.eql(u8, prop, "hasAttributes")) {
        return NativeResult.scalar(.{ .bool = c.xmlTextReaderHasAttributes(r) == 1 });
    }
    if (std.mem.eql(u8, prop, "hasValue")) {
        return NativeResult.scalar(.{ .bool = c.xmlTextReaderHasValue(r) == 1 });
    }
    if (std.mem.eql(u8, prop, "isDefault")) {
        return NativeResult.scalar(.{ .bool = c.xmlTextReaderIsDefault(r) == 1 });
    }
    if (std.mem.eql(u8, prop, "isEmptyElement")) {
        return NativeResult.scalar(.{ .bool = c.xmlTextReaderIsEmptyElement(r) == 1 });
    }
    return NativeResult.scalar(.null);
}

// ---------------- registration ----------------

fn cleanupPoolable(obj: *PhpObject) bool {
    cleanupObject(obj);
    return true;
}

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "XMLReader", .native_cleanup = cleanupPoolable };

    inline for (.{
        "open",                "XML",               "close",             "read",           "next",
        "moveToAttribute",     "moveToAttributeNo", "moveToAttributeNs", "moveToElement",  "moveToFirstAttribute",
        "moveToNextAttribute", "getAttribute",      "getAttributeNo",    "getAttributeNs", "readInnerXml",
        "readOuterXml",        "readString",        "isValid",           "expand",         "__get",
        "fromString",          "fromUri",
    }) |m| {
        try def.methods.put(a, m, .{ .name = m, .arity = 0 });
    }

    // class constants
    const xr_consts = .{
        .{ "NONE", 0 },        .{ "ELEMENT", 1 },          .{ "ATTRIBUTE", 2 },               .{ "TEXT", 3 },
        .{ "CDATA", 4 },       .{ "ENTITY_REF", 5 },       .{ "ENTITY", 6 },                  .{ "PI", 7 },
        .{ "COMMENT", 8 },     .{ "DOC", 9 },              .{ "DOC_TYPE", 10 },               .{ "DOC_FRAGMENT", 11 },
        .{ "NOTATION", 12 },   .{ "WHITESPACE", 13 },      .{ "SIGNIFICANT_WHITESPACE", 14 }, .{ "END_ELEMENT", 15 },
        .{ "END_ENTITY", 16 }, .{ "XML_DECLARATION", 17 }, .{ "LOADDTD", 1 },                 .{ "DEFAULTATTRS", 2 },
        .{ "VALIDATE", 3 },    .{ "SUBST_ENTITIES", 4 },
    };
    inline for (xr_consts) |k| {
        try def.constant_order.append(a, k[0]);
        try def.constant_names.put(a, k[0], {});
        try def.static_props.put(a, k[0], .{ .int = k[1] });
    }
    try vm.classes.put(a, "XMLReader", def);

    try vm.native_fns.put(a, "XMLReader::open", xrOpen);
    try vm.native_fns.put(a, "XMLReader::XML", xrXml);
    try vm.native_fns.put(a, "XMLReader::close", xrClose);
    try vm.native_fns.put(a, "XMLReader::read", xrRead);
    try vm.native_fns.put(a, "XMLReader::next", xrNext);
    try vm.native_fns.put(a, "XMLReader::moveToAttribute", xrMoveToAttribute);
    try vm.native_fns.put(a, "XMLReader::moveToAttributeNo", xrMoveToAttributeNo);
    try vm.native_fns.put(a, "XMLReader::moveToAttributeNs", xrMoveToAttributeNs);
    try vm.native_fns.put(a, "XMLReader::moveToElement", xrMoveToElement);
    try vm.native_fns.put(a, "XMLReader::moveToFirstAttribute", xrMoveToFirstAttribute);
    try vm.native_fns.put(a, "XMLReader::moveToNextAttribute", xrMoveToNextAttribute);
    try vm.native_fns.put(a, "XMLReader::getAttribute", xrGetAttribute);
    try vm.native_fns.put(a, "XMLReader::getAttributeNo", xrGetAttributeNo);
    try vm.native_fns.put(a, "XMLReader::getAttributeNs", xrGetAttributeNs);
    try vm.native_fns.put(a, "XMLReader::readInnerXml", xrReadInnerXml);
    try vm.native_fns.put(a, "XMLReader::readOuterXml", xrReadOuterXml);
    try vm.native_fns.put(a, "XMLReader::readString", xrReadString);
    try vm.native_fns.put(a, "XMLReader::isValid", xrIsValid);
    try vm.native_fns.put(a, "XMLReader::expand", xrExpand);
    try vm.native_fns.put(a, "XMLReader::__get", xrGet);
    try vm.native_fns.put(a, "XMLReader::fromString", xrFromString);
    try vm.native_fns.put(a, "XMLReader::fromUri", xrFromUri);

    // class constants for node types and load options. PHP exposes these as
    // XMLReader::ELEMENT, XMLReader::TEXT, etc. since zphp doesn't yet expose
    // class constants from native registration, also publish them as global
    // constants prefixed with XMLREADER_
    const consts = .{
        .{ "NONE", 0 },        .{ "ELEMENT", 1 },          .{ "ATTRIBUTE", 2 },               .{ "TEXT", 3 },
        .{ "CDATA", 4 },       .{ "ENTITY_REF", 5 },       .{ "ENTITY", 6 },                  .{ "PI", 7 },
        .{ "COMMENT", 8 },     .{ "DOC", 9 },              .{ "DOC_TYPE", 10 },               .{ "DOC_FRAGMENT", 11 },
        .{ "NOTATION", 12 },   .{ "WHITESPACE", 13 },      .{ "SIGNIFICANT_WHITESPACE", 14 }, .{ "END_ELEMENT", 15 },
        .{ "END_ENTITY", 16 }, .{ "XML_DECLARATION", 17 },
        // load options (subset)
        .{ "LOADDTD", 1 },                 .{ "DEFAULTATTRS", 2 },
        .{ "VALIDATE", 3 },    .{ "SUBST_ENTITIES", 4 },
    };
    inline for (consts) |k| {
        const upper = "XMLREADER_" ++ k[0];
        try vm.php_constants.put(a, upper, .{ .int = k[1] });
    }
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        cleanupObject(obj);
    }
}
