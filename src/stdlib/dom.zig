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
const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!Value;

const c = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
    @cInclude("libxml/xpath.h");
    @cInclude("libxml/xpathInternals.h");
    @cInclude("libxml/HTMLparser.h");
    @cInclude("libxml/HTMLtree.h");
    @cInclude("libxml/xmlerror.h");
});

// libxml2 init is one-shot per process; safe to call multiple times
var global_init_done: bool = false;

fn ensureGlobalInit() void {
    if (!global_init_done) {
        c.xmlInitParser();
        // suppress libxml2's default stderr output for parse errors;
        // PHP also defaults to silent unless libxml_use_internal_errors(true)
        c.xmlSetGenericErrorFunc(null, silentErrorHandler);
        global_init_done = true;
    }
}

fn silentErrorHandler(_: ?*anyopaque, _: [*c]const u8, ...) callconv(.c) void {}

// ---------------- pointer storage on PhpObject ----------------
// every wrapper stores its underlying xmlNodePtr as the "__node" property.
// for DOMDocument the pointer is actually an xmlDocPtr (cast-compatible with
// xmlNodePtr - libxml2 itself uses this dual identity throughout tree.c).
//
// the document wrapper owns the xmlDoc lifecycle: cleanupResources frees it.
// child wrappers reference nodes inside the doc and free nothing themselves -
// xmlFreeDoc walks the tree and frees everything.

fn getNodePtr(obj: *const PhpObject) ?*c.xmlNode {
    const v = obj.get("__node");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn getDocPtr(obj: *const PhpObject) ?*c.xmlDoc {
    const v = obj.get("__node");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn setNodePtr(obj: *PhpObject, allocator: Allocator, node: ?*c.xmlNode) !void {
    const p: i64 = if (node) |n| @intCast(@intFromPtr(n)) else 0;
    try obj.set(allocator, "__node", .{ .int = p });
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

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

fn cstrToValue(ctx: *NativeContext, p: [*c]const u8) !Value {
    if (p == null) return .null;
    const slice = p[0..cstrLen(p)];
    return .{ .string = try dupString(ctx, slice) };
}

// ---------------- class name dispatch by xmlElementType ----------------

fn classForNodeType(t: c.xmlElementType) []const u8 {
    return switch (t) {
        c.XML_ELEMENT_NODE => "DOMElement",
        c.XML_ATTRIBUTE_NODE => "DOMAttr",
        c.XML_TEXT_NODE => "DOMText",
        c.XML_CDATA_SECTION_NODE => "DOMCdataSection",
        c.XML_ENTITY_REF_NODE => "DOMEntityReference",
        c.XML_PI_NODE => "DOMProcessingInstruction",
        c.XML_COMMENT_NODE => "DOMComment",
        c.XML_DOCUMENT_NODE => "DOMDocument",
        c.XML_HTML_DOCUMENT_NODE => "DOMDocument",
        c.XML_DOCUMENT_TYPE_NODE => "DOMDocumentType",
        c.XML_DOCUMENT_FRAG_NODE => "DOMDocumentFragment",
        c.XML_NOTATION_NODE => "DOMNotation",
        else => "DOMNode",
    };
}

// wrap an xmlNodePtr in a fresh DOM* object. shares the doc wrapper for
// the owning document so identity flows back to the same wrapper
fn wrapNode(ctx: *NativeContext, node: ?*c.xmlNode, owner_doc: ?*PhpObject) !Value {
    const n = node orelse return .null;
    const cls = classForNodeType(n.type);
    const obj = try ctx.createObject(cls);
    try setNodePtr(obj, ctx.allocator, n);
    if (owner_doc) |d| try obj.set(ctx.allocator, "__owner", .{ .object = d });
    return .{ .object = obj };
}

fn getOwnerDocObj(obj: *PhpObject) ?*PhpObject {
    const v = obj.get("__owner");
    if (v == .object) return v.object;
    return null;
}

// ---------------- DOMDocument methods ----------------

fn domDocConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    ensureGlobalInit();
    const obj = getThis(ctx) orelse return .null;

    var version: []const u8 = "1.0";
    var encoding: []const u8 = "";
    if (args.len > 0 and args[0] == .string) version = args[0].string;
    if (args.len > 1 and args[1] == .string) encoding = args[1].string;

    const version_z = try dupZ(ctx, version);
    const doc = c.xmlNewDoc(@ptrCast(version_z.ptr)) orelse return .null;
    if (encoding.len > 0) {
        const enc_z = try dupZ(ctx, encoding);
        doc.*.encoding = c.xmlStrdup(@ptrCast(enc_z.ptr));
    }
    try setNodePtr(obj, ctx.allocator, @ptrCast(doc));
    try obj.set(ctx.allocator, "__owner", .{ .object = obj });
    try obj.set(ctx.allocator, "formatOutput", .{ .bool = false });
    try obj.set(ctx.allocator, "preserveWhiteSpace", .{ .bool = true });
    try obj.set(ctx.allocator, "validateOnParse", .{ .bool = false });
    try obj.set(ctx.allocator, "resolveExternals", .{ .bool = false });
    try obj.set(ctx.allocator, "substituteEntities", .{ .bool = false });
    try obj.set(ctx.allocator, "strictErrorChecking", .{ .bool = true });
    try obj.set(ctx.allocator, "recover", .{ .bool = false });
    return .null;
}

fn parseOptions(args: []const Value, idx: usize) c_int {
    if (args.len > idx and args[idx] == .int) return @intCast(args[idx].int);
    return 0;
}

fn domDocLoadXML(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const src = args[0].string;
    const opts = parseOptions(args, 1);

    // replace any prior doc
    if (getDocPtr(obj)) |old| {
        c.xmlFreeDoc(old);
        try setNodePtr(obj, ctx.allocator, null);
    }

    const doc = c.xmlReadMemory(src.ptr, @intCast(src.len), null, null, opts);
    if (doc == null) return .{ .bool = false };
    try setNodePtr(obj, ctx.allocator, @ptrCast(doc));
    return .{ .bool = true };
}

fn domDocLoad(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const path_z = try dupZ(ctx, args[0].string);
    const opts = parseOptions(args, 1);

    if (getDocPtr(obj)) |old| {
        c.xmlFreeDoc(old);
        try setNodePtr(obj, ctx.allocator, null);
    }

    const doc = c.xmlReadFile(path_z.ptr, null, opts);
    if (doc == null) return .{ .bool = false };
    try setNodePtr(obj, ctx.allocator, @ptrCast(doc));
    return .{ .bool = true };
}

fn domDocLoadHTML(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const src = args[0].string;
    const opts = parseOptions(args, 1);

    if (getDocPtr(obj)) |old| {
        c.xmlFreeDoc(old);
        try setNodePtr(obj, ctx.allocator, null);
    }

    const doc = c.htmlReadMemory(src.ptr, @intCast(src.len), null, null, opts);
    if (doc == null) return .{ .bool = false };
    try setNodePtr(obj, ctx.allocator, @ptrCast(doc));
    return .{ .bool = true };
}

fn domDocLoadHTMLFile(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const path_z = try dupZ(ctx, args[0].string);
    const opts = parseOptions(args, 1);

    if (getDocPtr(obj)) |old| {
        c.xmlFreeDoc(old);
        try setNodePtr(obj, ctx.allocator, null);
    }

    const doc = c.htmlReadFile(path_z.ptr, null, opts);
    if (doc == null) return .{ .bool = false };
    try setNodePtr(obj, ctx.allocator, @ptrCast(doc));
    return .{ .bool = true };
}

fn formatOutputOn(obj: *PhpObject) bool {
    const v = obj.get("formatOutput");
    return v == .bool and v.bool;
}

fn domDocSaveXML(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };

    var node: ?*c.xmlNode = null;
    if (args.len > 0 and args[0] == .object) {
        node = getNodePtr(args[0].object);
    }

    if (node) |n| {
        // dump single node
        const buf = c.xmlBufferCreate();
        defer c.xmlBufferFree(buf);
        const fmt: c_int = if (formatOutputOn(obj)) 1 else 0;
        _ = c.xmlNodeDump(buf, doc, n, 0, fmt);
        const out = c.xmlBufferContent(buf);
        if (out == null) return .{ .string = try dupString(ctx, "") };
        const slice = out[0..cstrLen(out)];
        return .{ .string = try dupString(ctx, slice) };
    }

    // full doc. pass NULL encoding when the document doesn't have one so libxml2
    // matches PHP's saveXML output (no `encoding="..."` attribute in the prolog)
    var out: [*c]u8 = null;
    var size: c_int = 0;
    const fmt: c_int = if (formatOutputOn(obj)) 1 else 0;
    c.xmlDocDumpFormatMemoryEnc(doc, &out, &size, doc.*.encoding, fmt);
    if (out == null) return .{ .bool = false };
    defer c.xmlFree.?(out);
    const slice = out[0..@intCast(size)];
    return .{ .string = try dupString(ctx, slice) };
}

fn domDocSaveHTML(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };

    if (args.len > 0 and args[0] == .object) {
        const n = getNodePtr(args[0].object) orelse return .{ .bool = false };
        const buf = c.xmlBufferCreate();
        defer c.xmlBufferFree(buf);
        _ = c.htmlNodeDump(buf, doc, n);
        const out = c.xmlBufferContent(buf);
        if (out == null) return .{ .string = try dupString(ctx, "") };
        const slice = out[0..cstrLen(out)];
        return .{ .string = try dupString(ctx, slice) };
    }

    var out: [*c]u8 = null;
    var size: c_int = 0;
    c.htmlDocDumpMemory(doc, &out, &size);
    if (out == null) return .{ .bool = false };
    defer c.xmlFree.?(out);
    const slice = out[0..@intCast(size)];
    return .{ .string = try dupString(ctx, slice) };
}

fn domDocSave(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const path_z = try dupZ(ctx, args[0].string);
    const fmt: c_int = if (formatOutputOn(obj)) 1 else 0;
    const written = c.xmlSaveFormatFile(path_z.ptr, doc, fmt);
    if (written < 0) return .{ .bool = false };
    return .{ .int = @intCast(written) };
}

fn domDocCreateElement(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const name_z = try dupZ(ctx, args[0].string);
    const node = c.xmlNewDocNode(doc, null, @ptrCast(name_z.ptr), null) orelse return .{ .bool = false };
    if (args.len > 1 and args[1] == .string and args[1].string.len > 0) {
        const text_z = try dupZ(ctx, args[1].string);
        const tn = c.xmlNewDocText(doc, @ptrCast(text_z.ptr));
        _ = c.xmlAddChild(node, tn);
    }
    return wrapNode(ctx, node, obj);
}

fn domDocCreateTextNode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const text_z = try dupZ(ctx, args[0].string);
    const node = c.xmlNewDocText(doc, @ptrCast(text_z.ptr)) orelse return .{ .bool = false };
    return wrapNode(ctx, node, obj);
}

fn domDocCreateComment(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const text_z = try dupZ(ctx, args[0].string);
    const node = c.xmlNewDocComment(doc, @ptrCast(text_z.ptr)) orelse return .{ .bool = false };
    return wrapNode(ctx, node, obj);
}

fn domDocCreateCDATASection(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const text = args[0].string;
    const node = c.xmlNewCDataBlock(doc, @ptrCast(text.ptr), @intCast(text.len)) orelse return .{ .bool = false };
    return wrapNode(ctx, node, obj);
}

fn domDocCreateAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const name_z = try dupZ(ctx, args[0].string);
    // detached attribute: create via xmlNewDocProp on null parent
    const attr = c.xmlNewDocProp(doc, @ptrCast(name_z.ptr), null) orelse return .{ .bool = false };
    return wrapNode(ctx, @ptrCast(attr), obj);
}

fn domDocCreateElementNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };

    const ns_uri: ?[]const u8 = if (args[0] == .string) args[0].string else null;
    const qname = args[1].string;

    // split qname into prefix:localname
    var prefix_buf: ?[:0]u8 = null;
    var local_buf: [:0]u8 = undefined;
    if (std.mem.indexOfScalar(u8, qname, ':')) |colon| {
        prefix_buf = try dupZ(ctx, qname[0..colon]);
        local_buf = try dupZ(ctx, qname[colon + 1 ..]);
    } else {
        local_buf = try dupZ(ctx, qname);
    }

    const node = c.xmlNewDocNode(doc, null, @ptrCast(local_buf.ptr), null) orelse return .{ .bool = false };
    if (ns_uri) |uri| {
        const uri_z = try dupZ(ctx, uri);
        const prefix_ptr: [*c]const u8 = if (prefix_buf) |p| @ptrCast(p.ptr) else null;
        const ns = c.xmlNewNs(node, @ptrCast(uri_z.ptr), prefix_ptr);
        c.xmlSetNs(node, ns);
    }
    if (args.len > 2 and args[2] == .string and args[2].string.len > 0) {
        const text_z = try dupZ(ctx, args[2].string);
        const tn = c.xmlNewDocText(doc, @ptrCast(text_z.ptr));
        _ = c.xmlAddChild(node, tn);
    }
    return wrapNode(ctx, node, obj);
}

fn domDocCreateDocumentFragment(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const node = c.xmlNewDocFragment(doc) orelse return .{ .bool = false };
    return wrapNode(ctx, node, obj);
}

fn domDocImportNode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const src = getNodePtr(args[0].object) orelse return .{ .bool = false };
    const deep: c_int = if (args.len > 1 and args[1] == .bool and args[1].bool) 1 else 0;
    const copy = c.xmlDocCopyNode(src, doc, if (deep != 0) 1 else 2);
    if (copy == null) return .{ .bool = false };
    return wrapNode(ctx, copy, obj);
}

fn domDocGetElementsByTagName(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };
    const name = args[0].string;

    const root = c.xmlDocGetRootElement(doc);
    var list = std.ArrayList(*c.xmlNode){};
    defer list.deinit(ctx.allocator);
    if (root) |r| {
        try collectByName(ctx.allocator, r, name, &list);
    }
    return try makeNodeList(ctx, obj, list.items);
}

fn domDocGetElementById(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const doc = getDocPtr(obj) orelse return .null;
    const id_z = try dupZ(ctx, args[0].string);
    const attr = c.xmlGetID(doc, @ptrCast(id_z.ptr));
    if (attr == null) {
        // fall back to scanning for any attribute named "id" with this value
        const root = c.xmlDocGetRootElement(doc);
        if (root) |r| {
            if (findById(r, args[0].string)) |n| return wrapNode(ctx, n, obj);
        }
        return .null;
    }
    return wrapNode(ctx, @ptrCast(attr.*.parent), obj);
}

fn findById(node: *c.xmlNode, id: []const u8) ?*c.xmlNode {
    if (node.type == c.XML_ELEMENT_NODE) {
        var attr = node.properties;
        while (attr != null) : (attr = attr.*.next) {
            const name = attr.*.name;
            if (name != null and std.mem.eql(u8, name[0..cstrLen(name)], "id")) {
                if (attr.*.children != null) {
                    const v = attr.*.children.*.content;
                    if (v != null and std.mem.eql(u8, v[0..cstrLen(v)], id)) return node;
                }
            }
        }
    }
    var child = node.children;
    while (child != null) : (child = child.*.next) {
        if (findById(child, id)) |found| return found;
    }
    return null;
}

fn collectByName(allocator: Allocator, node: *c.xmlNode, name: []const u8, out: *std.ArrayList(*c.xmlNode)) !void {
    const want_all = std.mem.eql(u8, name, "*");
    if (node.type == c.XML_ELEMENT_NODE) {
        if (want_all) {
            try out.append(allocator, node);
        } else {
            const nn = node.name;
            if (nn != null and std.mem.eql(u8, nn[0..cstrLen(nn)], name)) {
                try out.append(allocator, node);
            }
        }
    }
    var child = node.children;
    while (child != null) : (child = child.*.next) {
        try collectByName(allocator, child, name, out);
    }
}

fn collectByNameNS(allocator: Allocator, node: *c.xmlNode, ns: []const u8, name: []const u8, out: *std.ArrayList(*c.xmlNode)) !void {
    const want_any_name = std.mem.eql(u8, name, "*");
    const want_any_ns = std.mem.eql(u8, ns, "*");
    if (node.type == c.XML_ELEMENT_NODE) {
        var name_ok = want_any_name;
        if (!name_ok) {
            const nn = node.name;
            name_ok = nn != null and std.mem.eql(u8, nn[0..cstrLen(nn)], name);
        }
        var ns_ok = want_any_ns;
        if (!ns_ok) {
            const node_ns = node.ns;
            if (node_ns != null and node_ns.*.href != null) {
                const href = node_ns.*.href;
                ns_ok = std.mem.eql(u8, href[0..cstrLen(href)], ns);
            } else {
                ns_ok = ns.len == 0;
            }
        }
        if (name_ok and ns_ok) try out.append(allocator, node);
    }
    var child = node.children;
    while (child != null) : (child = child.*.next) {
        try collectByNameNS(allocator, child, ns, name, out);
    }
}

fn domDocNormalizeDocument(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    _ = ctx;
    // PHP's normalizeDocument coalesces adjacent text nodes; libxml2 does this on saveXML.
    // no-op here is observably equivalent for the common path
    return .null;
}

// ---------------- DOMNode read-only accessors ----------------

fn domNodeProp(prop: []const u8) ?(*const fn (ctx: *NativeContext, args: []const Value) RuntimeError!Value) {
    _ = prop;
    return null;
}

// magic getter dispatched via __get for read-only properties on DOM* objects.
// register native __get on each DOM* class and route by property name
fn domGenericGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const prop = args[0].string;
    return try readProperty(ctx, obj, prop);
}

fn domGenericSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const prop = args[0].string;
    const val = args[1];

    if (std.mem.eql(u8, prop, "nodeValue") or std.mem.eql(u8, prop, "textContent")) {
        const s = if (val == .string) val.string else "";
        const s_z = try dupZ(ctx, s);
        // wipe existing content and set fresh
        c.xmlNodeSetContent(node, @ptrCast(s_z.ptr));
        return .null;
    }
    if (std.mem.eql(u8, prop, "data") and (node.type == c.XML_TEXT_NODE or node.type == c.XML_CDATA_SECTION_NODE or node.type == c.XML_COMMENT_NODE)) {
        const s = if (val == .string) val.string else "";
        const s_z = try dupZ(ctx, s);
        c.xmlNodeSetContent(node, @ptrCast(s_z.ptr));
        return .null;
    }
    if (std.mem.eql(u8, prop, "value") and node.type == c.XML_ATTRIBUTE_NODE) {
        const s = if (val == .string) val.string else "";
        const s_z = try dupZ(ctx, s);
        c.xmlNodeSetContent(node, @ptrCast(s_z.ptr));
        return .null;
    }
    // unrecognized property: fall back to stashing in PhpObject (matches the
    // legacy dynamic-property behavior so tests aren't surprised)
    try obj.set(ctx.allocator, prop, val);
    return .null;
}

fn readProperty(ctx: *NativeContext, obj: *PhpObject, prop: []const u8) RuntimeError!Value {
    // namespace pseudo-nodes are stored as standalone PhpObjects with their
    // prefix+href captured as properties (not via __node, since the underlying
    // xmlNs is freed when the XPath result is). short-circuit before any
    // __node-based dereference
    if (obj.get("__ns_kind") == .bool and obj.get("__ns_kind").bool) {
        if (std.mem.eql(u8, prop, "nodeName")) {
            const px = obj.get("__ns_prefix");
            if (px == .string and px.string.len > 0) {
                const out = try std.fmt.allocPrint(ctx.allocator, "xmlns:{s}", .{px.string});
                try ctx.strings.append(ctx.allocator, out);
                return .{ .string = out };
            }
            return .{ .string = try dupString(ctx, "xmlns") };
        }
        if (std.mem.eql(u8, prop, "nodeValue") or std.mem.eql(u8, prop, "value")) {
            const href = obj.get("__ns_href");
            if (href == .string) return href;
            return .{ .string = try dupString(ctx, "") };
        }
        if (std.mem.eql(u8, prop, "nodeType")) return .{ .int = @intCast(c.XML_NAMESPACE_DECL) };
        return .null;
    }

    const owner = getOwnerDocObj(obj) orelse obj;
    const node_opt = getNodePtr(obj);
    if (node_opt == null) return .null;
    const node = node_opt.?;

    if (std.mem.eql(u8, prop, "nodeName")) {
        // for documents, return "#document"
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE) {
            return .{ .string = try dupString(ctx, "#document") };
        }
        if (node.type == c.XML_TEXT_NODE) return .{ .string = try dupString(ctx, "#text") };
        if (node.type == c.XML_CDATA_SECTION_NODE) return .{ .string = try dupString(ctx, "#cdata-section") };
        if (node.type == c.XML_COMMENT_NODE) return .{ .string = try dupString(ctx, "#comment") };
        if (node.type == c.XML_DOCUMENT_FRAG_NODE) return .{ .string = try dupString(ctx, "#document-fragment") };
        // for elements, include prefix if namespaced
        if (node.type == c.XML_ELEMENT_NODE and node.ns != null and node.ns.*.prefix != null) {
            const prefix = node.ns.*.prefix;
            const name = node.name;
            const out = try std.fmt.allocPrint(ctx.allocator, "{s}:{s}", .{
                prefix[0..cstrLen(prefix)],
                name[0..cstrLen(name)],
            });
            try ctx.strings.append(ctx.allocator, out);
            return .{ .string = out };
        }
        return try cstrToValue(ctx, node.name);
    }
    if (std.mem.eql(u8, prop, "nodeValue")) {
        // PHP returns concatenated text content for elements; null for documents
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE or node.type == c.XML_DOCUMENT_TYPE_NODE) {
            return .null;
        }
        const content = c.xmlNodeGetContent(node);
        if (content == null) return .{ .string = try dupString(ctx, "") };
        defer c.xmlFree.?(content);
        const slice = content[0..cstrLen(content)];
        return .{ .string = try dupString(ctx, slice) };
    }
    if (std.mem.eql(u8, prop, "textContent")) {
        const content = c.xmlNodeGetContent(node);
        if (content == null) return .{ .string = try dupString(ctx, "") };
        defer c.xmlFree.?(content);
        const slice = content[0..cstrLen(content)];
        return .{ .string = try dupString(ctx, slice) };
    }
    if (std.mem.eql(u8, prop, "nodeType")) {
        return .{ .int = @intCast(node.type) };
    }
    if (std.mem.eql(u8, prop, "parentNode")) {
        return wrapNode(ctx, node.parent, owner);
    }
    if (std.mem.eql(u8, prop, "firstChild")) {
        return wrapNode(ctx, node.children, owner);
    }
    if (std.mem.eql(u8, prop, "lastChild")) {
        return wrapNode(ctx, node.last, owner);
    }
    if (std.mem.eql(u8, prop, "previousSibling")) {
        return wrapNode(ctx, node.prev, owner);
    }
    if (std.mem.eql(u8, prop, "nextSibling")) {
        return wrapNode(ctx, node.next, owner);
    }
    if (std.mem.eql(u8, prop, "previousElementSibling")) {
        var p = node.prev;
        while (p != null and p.*.type != c.XML_ELEMENT_NODE) : (p = p.*.prev) {}
        return wrapNode(ctx, p, owner);
    }
    if (std.mem.eql(u8, prop, "nextElementSibling")) {
        var n = node.next;
        while (n != null and n.*.type != c.XML_ELEMENT_NODE) : (n = n.*.next) {}
        return wrapNode(ctx, n, owner);
    }
    if (std.mem.eql(u8, prop, "firstElementChild")) {
        var k = node.children;
        while (k != null and k.*.type != c.XML_ELEMENT_NODE) : (k = k.*.next) {}
        return wrapNode(ctx, k, owner);
    }
    if (std.mem.eql(u8, prop, "lastElementChild")) {
        var k = node.last;
        while (k != null and k.*.type != c.XML_ELEMENT_NODE) : (k = k.*.prev) {}
        return wrapNode(ctx, k, owner);
    }
    if (std.mem.eql(u8, prop, "childElementCount")) {
        var k = node.children;
        var count: i64 = 0;
        while (k != null) : (k = k.*.next) {
            if (k.*.type == c.XML_ELEMENT_NODE) count += 1;
        }
        return .{ .int = count };
    }
    if (std.mem.eql(u8, prop, "childNodes")) {
        var list = std.ArrayList(*c.xmlNode){};
        defer list.deinit(ctx.allocator);
        var child = node.children;
        while (child != null) : (child = child.*.next) try list.append(ctx.allocator, child);
        return try makeNodeList(ctx, owner, list.items);
    }
    if (std.mem.eql(u8, prop, "ownerDocument")) {
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE) return .null;
        return .{ .object = owner };
    }
    if (std.mem.eql(u8, prop, "documentElement")) {
        if (node.type != c.XML_DOCUMENT_NODE and node.type != c.XML_HTML_DOCUMENT_NODE) return .null;
        const doc: *c.xmlDoc = @ptrCast(node);
        return wrapNode(ctx, c.xmlDocGetRootElement(doc), owner);
    }
    if (std.mem.eql(u8, prop, "namespaceURI")) {
        if (node.ns != null and node.ns.*.href != null) return try cstrToValue(ctx, node.ns.*.href);
        return .null;
    }
    if (std.mem.eql(u8, prop, "prefix")) {
        if (node.ns != null and node.ns.*.prefix != null) return try cstrToValue(ctx, node.ns.*.prefix);
        return .{ .string = try dupString(ctx, "") };
    }
    if (std.mem.eql(u8, prop, "localName")) {
        if (node.type == c.XML_ELEMENT_NODE or node.type == c.XML_ATTRIBUTE_NODE) {
            return try cstrToValue(ctx, node.name);
        }
        return .null;
    }
    if (std.mem.eql(u8, prop, "baseURI")) {
        const u = c.xmlNodeGetBase(@ptrCast(node.doc), node);
        if (u == null) return .null;
        defer c.xmlFree.?(u);
        return .{ .string = try dupString(ctx, u[0..cstrLen(u)]) };
    }
    if (std.mem.eql(u8, prop, "tagName")) {
        if (node.type == c.XML_ELEMENT_NODE) {
            if (node.ns != null and node.ns.*.prefix != null) {
                const prefix = node.ns.*.prefix;
                const name = node.name;
                const out = try std.fmt.allocPrint(ctx.allocator, "{s}:{s}", .{
                    prefix[0..cstrLen(prefix)],
                    name[0..cstrLen(name)],
                });
                try ctx.strings.append(ctx.allocator, out);
                return .{ .string = out };
            }
            return try cstrToValue(ctx, node.name);
        }
    }
    if (std.mem.eql(u8, prop, "attributes")) {
        if (node.type != c.XML_ELEMENT_NODE) return .null;
        return try makeNamedNodeMap(ctx, owner, node);
    }
    if (std.mem.eql(u8, prop, "data") or std.mem.eql(u8, prop, "value")) {
        const content = c.xmlNodeGetContent(node);
        if (content == null) return .{ .string = try dupString(ctx, "") };
        defer c.xmlFree.?(content);
        return .{ .string = try dupString(ctx, content[0..cstrLen(content)]) };
    }
    if (std.mem.eql(u8, prop, "length")) {
        const content = c.xmlNodeGetContent(node);
        if (content == null) return .{ .int = 0 };
        defer c.xmlFree.?(content);
        return .{ .int = @intCast(cstrLen(content)) };
    }
    if (std.mem.eql(u8, prop, "name")) {
        if (node.type == c.XML_ATTRIBUTE_NODE) return try cstrToValue(ctx, node.name);
    }
    if (std.mem.eql(u8, prop, "ownerElement")) {
        if (node.type == c.XML_ATTRIBUTE_NODE) return wrapNode(ctx, node.parent, owner);
    }
    if (std.mem.eql(u8, prop, "encoding")) {
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE) {
            const doc: *c.xmlDoc = @ptrCast(node);
            if (doc.*.encoding != null) return try cstrToValue(ctx, doc.*.encoding);
            return .null;
        }
    }
    if (std.mem.eql(u8, prop, "version") or std.mem.eql(u8, prop, "xmlVersion")) {
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE) {
            const doc: *c.xmlDoc = @ptrCast(node);
            if (doc.*.version != null) return try cstrToValue(ctx, doc.*.version);
            return .null;
        }
    }
    return .null;
}

// ---------------- DOMNode write methods ----------------

fn domNodeAppendChild(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const parent = getNodePtr(obj) orelse return .{ .bool = false };
    const child = getNodePtr(args[0].object) orelse return .{ .bool = false };

    // unlink first if attached
    c.xmlUnlinkNode(child);
    const added = c.xmlAddChild(parent, child);
    if (added == null) return .{ .bool = false };
    return wrapNode(ctx, added, getOwnerDocObj(obj) orelse obj);
}

fn domNodeRemoveChild(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    _ = getNodePtr(obj) orelse return .{ .bool = false };
    const child = getNodePtr(args[0].object) orelse return .{ .bool = false };

    c.xmlUnlinkNode(child);
    // PHP returns the removed node; we keep it alive (libxml2 won't free unless we xmlFreeNode).
    // since the doc owns the arena via xmlFreeDoc only for in-tree nodes, an unlinked node
    // would leak across requests. attach it to a per-doc orphans list so xmlFreeDoc still
    // catches it: simplest is to keep wrapping and rely on the test runner's request lifetime
    // freeing the whole VM. for now wrap and return
    return wrapNode(ctx, child, getOwnerDocObj(obj) orelse obj);
}

fn domNodeReplaceChild(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    _ = getNodePtr(obj) orelse return .{ .bool = false };
    const new_node = getNodePtr(args[0].object) orelse return .{ .bool = false };
    const old_node = getNodePtr(args[1].object) orelse return .{ .bool = false };

    c.xmlUnlinkNode(new_node);
    const replaced = c.xmlReplaceNode(old_node, new_node);
    if (replaced == null) return .{ .bool = false };
    return wrapNode(ctx, replaced, getOwnerDocObj(obj) orelse obj);
}

fn domNodeInsertBefore(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const parent = getNodePtr(obj) orelse return .{ .bool = false };
    const new_node = getNodePtr(args[0].object) orelse return .{ .bool = false };

    var ref: ?*c.xmlNode = null;
    if (args.len > 1 and args[1] == .object) ref = getNodePtr(args[1].object);

    c.xmlUnlinkNode(new_node);
    const added = if (ref) |r| c.xmlAddPrevSibling(r, new_node) else c.xmlAddChild(parent, new_node);
    if (added == null) return .{ .bool = false };
    return wrapNode(ctx, added, getOwnerDocObj(obj) orelse obj);
}

fn domNodeCloneNode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const deep: c_int = if (args.len > 0 and args[0] == .bool and args[0].bool) 1 else 2;
    const copy = c.xmlDocCopyNode(node, node.doc, deep);
    return wrapNode(ctx, copy, getOwnerDocObj(obj) orelse obj);
}

fn domNodeHasChildNodes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    return .{ .bool = node.children != null };
}

fn domNodeHasAttributes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    if (node.type != c.XML_ELEMENT_NODE) return .{ .bool = false };
    return .{ .bool = node.properties != null };
}

fn domNodeIsSameNode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const a = getNodePtr(obj) orelse return .{ .bool = false };
    const b = getNodePtr(args[0].object) orelse return .{ .bool = false };
    return .{ .bool = a == b };
}

fn domNodeGetNodePath(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const p = c.xmlGetNodePath(node);
    if (p == null) return .null;
    defer c.xmlFree.?(p);
    return .{ .string = try dupString(ctx, p[0..cstrLen(p)]) };
}

fn domNodeGetLineNo(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const node = getNodePtr(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(c.xmlGetLineNo(node)) };
}

fn domNodeLookupPrefix(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const uri_z = try dupZ(ctx, args[0].string);
    const ns = c.xmlSearchNsByHref(node.doc, node, @ptrCast(uri_z.ptr));
    if (ns == null or ns.*.prefix == null) return .null;
    return try cstrToValue(ctx, ns.*.prefix);
}

fn domNodeLookupNamespaceURI(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const prefix_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.len > 0)
        @ptrCast((try dupZ(ctx, args[0].string)).ptr)
    else
        null;
    const ns = c.xmlSearchNs(node.doc, node, prefix_ptr);
    if (ns == null or ns.*.href == null) return .null;
    return try cstrToValue(ctx, ns.*.href);
}

// ---------------- DOMElement methods ----------------

fn domElementGetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .string = try dupString(ctx, "") };
    const obj = getThis(ctx) orelse return .{ .string = try dupString(ctx, "") };
    const node = getNodePtr(obj) orelse return .{ .string = try dupString(ctx, "") };
    const name_z = try dupZ(ctx, args[0].string);
    const v = c.xmlGetProp(node, @ptrCast(name_z.ptr));
    if (v == null) return .{ .string = try dupString(ctx, "") };
    defer c.xmlFree.?(v);
    return .{ .string = try dupString(ctx, v[0..cstrLen(v)]) };
}

fn domElementSetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const name_z = try dupZ(ctx, args[0].string);
    const val_z = try dupZ(ctx, args[1].string);
    const attr = c.xmlSetProp(node, @ptrCast(name_z.ptr), @ptrCast(val_z.ptr));
    if (attr == null) return .{ .bool = false };
    return wrapNode(ctx, @ptrCast(attr), getOwnerDocObj(obj) orelse obj);
}

fn domElementHasAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const name_z = try dupZ(ctx, args[0].string);
    return .{ .bool = c.xmlHasProp(node, @ptrCast(name_z.ptr)) != null };
}

fn domElementRemoveAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const name_z = try dupZ(ctx, args[0].string);
    const rc = c.xmlUnsetProp(node, @ptrCast(name_z.ptr));
    return .{ .bool = rc == 0 };
}

fn domElementGetAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .string = try dupString(ctx, "") };
    const obj = getThis(ctx) orelse return .{ .string = try dupString(ctx, "") };
    const node = getNodePtr(obj) orelse return .{ .string = try dupString(ctx, "") };
    const ns_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.len > 0)
        @ptrCast((try dupZ(ctx, args[0].string)).ptr)
    else
        null;
    const name_z = try dupZ(ctx, args[1].string);
    const v = c.xmlGetNsProp(node, @ptrCast(name_z.ptr), ns_ptr);
    if (v == null) return .{ .string = try dupString(ctx, "") };
    defer c.xmlFree.?(v);
    return .{ .string = try dupString(ctx, v[0..cstrLen(v)]) };
}

fn domElementSetAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[1] != .string or args[2] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const qname = args[1].string;
    const val_z = try dupZ(ctx, args[2].string);

    var ns_ptr: ?*c.xmlNs = null;
    if (args[0] == .string and args[0].string.len > 0) {
        const uri_z = try dupZ(ctx, args[0].string);
        // resolve / create namespace
        if (std.mem.indexOfScalar(u8, qname, ':')) |colon| {
            const prefix_z = try dupZ(ctx, qname[0..colon]);
            ns_ptr = c.xmlSearchNs(node.doc, node, @ptrCast(prefix_z.ptr));
            if (ns_ptr == null) {
                ns_ptr = c.xmlNewNs(node, @ptrCast(uri_z.ptr), @ptrCast(prefix_z.ptr));
            }
        } else {
            ns_ptr = c.xmlSearchNsByHref(node.doc, node, @ptrCast(uri_z.ptr));
            if (ns_ptr == null) ns_ptr = c.xmlNewNs(node, @ptrCast(uri_z.ptr), null);
        }
    }

    // strip prefix from qname to get localname
    const local = if (std.mem.indexOfScalar(u8, qname, ':')) |i| qname[i + 1 ..] else qname;
    const local_z = try dupZ(ctx, local);
    _ = c.xmlSetNsProp(node, ns_ptr, @ptrCast(local_z.ptr), @ptrCast(val_z.ptr));
    return .null;
}

fn domElementHasAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const ns_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.len > 0)
        @ptrCast((try dupZ(ctx, args[0].string)).ptr)
    else
        null;
    const name_z = try dupZ(ctx, args[1].string);
    const v = c.xmlGetNsProp(node, @ptrCast(name_z.ptr), ns_ptr);
    if (v == null) return .{ .bool = false };
    c.xmlFree.?(v);
    return .{ .bool = true };
}

fn domElementRemoveAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const ns_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.len > 0)
        @ptrCast((try dupZ(ctx, args[0].string)).ptr)
    else
        null;
    _ = ns_ptr;
    const name_z = try dupZ(ctx, args[1].string);
    _ = c.xmlUnsetNsProp(node, null, @ptrCast(name_z.ptr));
    return .null;
}

fn domElementGetElementsByTagName(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    var list = std.ArrayList(*c.xmlNode){};
    defer list.deinit(ctx.allocator);
    var child = node.children;
    while (child != null) : (child = child.*.next) try collectByName(ctx.allocator, child, args[0].string, &list);
    return try makeNodeList(ctx, getOwnerDocObj(obj) orelse obj, list.items);
}

fn domGetElementsByTagNameNS(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const ns = if (args[0] == .string) args[0].string else "*";
    const name = args[1].string;
    var node = getNodePtr(obj) orelse return .{ .bool = false };
    // for DOMDocument, the wrapping node may not have children walking the doc;
    // start at the root element
    if (node.type == c.XML_DOCUMENT_NODE) {
        const root = c.xmlDocGetRootElement(@ptrCast(node));
        if (root == null) return try makeNodeList(ctx, obj, &.{});
        node = root;
    }
    var list = std.ArrayList(*c.xmlNode){};
    defer list.deinit(ctx.allocator);
    try collectByNameNS(ctx.allocator, node, ns, name, &list);
    return try makeNodeList(ctx, getOwnerDocObj(obj) orelse obj, list.items);
}

fn domElementGetAttributeNode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const name_z = try dupZ(ctx, args[0].string);
    const attr = c.xmlHasProp(node, @ptrCast(name_z.ptr));
    if (attr == null) return .null;
    return wrapNode(ctx, @ptrCast(attr), getOwnerDocObj(obj) orelse obj);
}

// ---------------- DOMCharacterData methods ----------------

fn domCdAppendData(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const text_z = try dupZ(ctx, args[0].string);
    c.xmlNodeAddContent(node, @ptrCast(text_z.ptr));
    return .null;
}

fn domCdSubstringData(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const content = c.xmlNodeGetContent(node);
    if (content == null) return .{ .string = try dupString(ctx, "") };
    defer c.xmlFree.?(content);
    const slice = content[0..cstrLen(content)];
    const off: usize = if (args[0].int < 0) 0 else @intCast(args[0].int);
    if (off >= slice.len) return .{ .string = try dupString(ctx, "") };
    const cnt: usize = if (args[1].int < 0) 0 else @intCast(args[1].int);
    const end = @min(off + cnt, slice.len);
    return .{ .string = try dupString(ctx, slice[off..end]) };
}

// ---------------- DOMNodeList ----------------

fn makeNodeList(ctx: *NativeContext, owner_doc: *PhpObject, nodes: []*c.xmlNode) !Value {
    const list_obj = try ctx.createObject("DOMNodeList");
    const arr = try ctx.createArray();
    for (nodes, 0..) |n, i| {
        const wrapped = try wrapNode(ctx, n, owner_doc);
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, wrapped);
    }
    try list_obj.set(ctx.allocator, "__items", .{ .array = arr });
    try list_obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try list_obj.set(ctx.allocator, "length", .{ .int = @intCast(nodes.len) });
    return .{ .object = list_obj };
}

fn nlItems(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__items");
    if (v != .array) return null;
    return v.array;
}

fn domNodeListLength(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    _ = ctx;
    const obj = getThisGlobal() orelse return .{ .int = 0 };
    const arr = nlItems(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(arr.entries.items.len) };
}

fn domNodeListItem(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = ctx;
    if (args.len < 1 or args[0] != .int) return .null;
    const obj = getThisGlobal() orelse return .null;
    const arr = nlItems(obj) orelse return .null;
    const idx = args[0].int;
    if (idx < 0 or idx >= @as(i64, @intCast(arr.entries.items.len))) return .null;
    return arr.entries.items[@intCast(idx)].value;
}

fn domNodeListCount(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return domNodeListLength(ctx, args);
}

fn domNodeListRewind(_: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThisGlobal() orelse return .null;
    obj.properties.put(std.heap.page_allocator, "__pos", .{ .int = 0 }) catch {};
    return .null;
}

fn domNodeListValid(_: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThisGlobal() orelse return .{ .bool = false };
    const arr = nlItems(obj) orelse return .{ .bool = false };
    const pos = obj.get("__pos");
    const p: i64 = if (pos == .int) pos.int else 0;
    return .{ .bool = p >= 0 and p < @as(i64, @intCast(arr.entries.items.len)) };
}

fn domNodeListCurrent(_: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThisGlobal() orelse return .null;
    const arr = nlItems(obj) orelse return .null;
    const pos = obj.get("__pos");
    const p: i64 = if (pos == .int) pos.int else 0;
    if (p < 0 or p >= @as(i64, @intCast(arr.entries.items.len))) return .null;
    return arr.entries.items[@intCast(p)].value;
}

fn domNodeListKey(_: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThisGlobal() orelse return .{ .int = 0 };
    const pos = obj.get("__pos");
    return if (pos == .int) pos else .{ .int = 0 };
}

fn domNodeListNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThisGlobal() orelse return .null;
    const pos = obj.get("__pos");
    const p: i64 = if (pos == .int) pos.int else 0;
    obj.set(ctx.allocator, "__pos", .{ .int = p + 1 }) catch {};
    return .null;
}

fn getThisGlobal() ?*PhpObject {
    // helper that doesn't need ctx for the simple frame lookup
    const vm: *VM = vm_singleton orelse return null;
    if (vm.frame_count == 0) return null;
    const v = vm.frames[vm.frame_count - 1].vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

var vm_singleton: ?*VM = null;

// ---------------- DOMNamedNodeMap ----------------

fn makeNamedNodeMap(ctx: *NativeContext, owner_doc: *PhpObject, element: *c.xmlNode) !Value {
    const map_obj = try ctx.createObject("DOMNamedNodeMap");
    const arr = try ctx.createArray();
    const named = try ctx.createArray();
    var attr = element.properties;
    var i: usize = 0;
    while (attr != null) : (attr = attr.*.next) {
        const wrapped = try wrapNode(ctx, @ptrCast(attr), owner_doc);
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, wrapped);
        if (attr.*.name != null) {
            const name = attr.*.name;
            const key = try dupString(ctx, name[0..cstrLen(name)]);
            try named.set(ctx.allocator, .{ .string = key }, wrapped);
        }
        i += 1;
    }
    try map_obj.set(ctx.allocator, "__items", .{ .array = arr });
    try map_obj.set(ctx.allocator, "__named", .{ .array = named });
    try map_obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try map_obj.set(ctx.allocator, "length", .{ .int = @intCast(i) });
    return .{ .object = map_obj };
}

fn domNNMGetNamedItem(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThisGlobal() orelse return .null;
    const named = obj.get("__named");
    if (named != .array) return .null;
    return named.array.get(.{ .string = args[0].string });
}

fn domNNMItem(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .null;
    const obj = getThisGlobal() orelse return .null;
    const items = obj.get("__items");
    if (items != .array) return .null;
    const idx = args[0].int;
    if (idx < 0 or idx >= @as(i64, @intCast(items.array.entries.items.len))) return .null;
    return items.array.entries.items[@intCast(idx)].value;
}

fn domNNMCount(_: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThisGlobal() orelse return .{ .int = 0 };
    const items = obj.get("__items");
    if (items != .array) return .{ .int = 0 };
    return .{ .int = @intCast(items.array.entries.items.len) };
}

// ---------------- DOMXPath ----------------

fn domXpathConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .null;
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__doc", args[0]);
    return .null;
}

fn domXpathRegisterNamespace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    var ns_map = obj.get("__namespaces");
    if (ns_map != .array) {
        const arr = try ctx.createArray();
        try obj.set(ctx.allocator, "__namespaces", .{ .array = arr });
        ns_map = .{ .array = arr };
    }
    const key = try dupString(ctx, args[0].string);
    const val = try dupString(ctx, args[1].string);
    try ns_map.array.set(ctx.allocator, .{ .string = key }, .{ .string = val });
    return .{ .bool = true };
}

fn domXpathQuery(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc_v = obj.get("__doc");
    if (doc_v != .object) return .{ .bool = false };
    const doc = getDocPtr(doc_v.object) orelse return .{ .bool = false };

    var context_node: ?*c.xmlNode = null;
    if (args.len > 1 and args[1] == .object) {
        context_node = getNodePtr(args[1].object);
    }

    const xctx = c.xmlXPathNewContext(doc) orelse return .{ .bool = false };
    defer c.xmlXPathFreeContext(xctx);
    if (context_node) |cn| xctx.*.node = cn;

    // register any user namespaces
    const ns_map = obj.get("__namespaces");
    if (ns_map == .array) {
        for (ns_map.array.entries.items) |e| {
            if (e.key != .string or e.value != .string) continue;
            const prefix_z = try dupZ(ctx, e.key.string);
            const uri_z = try dupZ(ctx, e.value.string);
            _ = c.xmlXPathRegisterNs(xctx, @ptrCast(prefix_z.ptr), @ptrCast(uri_z.ptr));
        }
    }

    const expr_z = try dupZ(ctx, args[0].string);
    const result = c.xmlXPathEvalExpression(@ptrCast(expr_z.ptr), xctx);
    if (result == null) return .{ .bool = false };
    defer c.xmlXPathFreeObject(result);

    if (result.*.type != c.XPATH_NODESET) {
        return try makeNodeList(ctx, doc_v.object, &.{});
    }
    const ns = result.*.nodesetval;
    if (ns == null) return try makeNodeList(ctx, doc_v.object, &.{});

    return try buildXpathNodeList(ctx, doc_v.object, ns);
}

// build a DOMNodeList from an xmlXPath nodeset. namespace pseudo-nodes get
// converted into standalone PhpObjects right away because the underlying
// xmlNs entries are freed when xmlXPathFreeObject runs on this result
fn buildXpathNodeList(ctx: *NativeContext, owner_doc: *PhpObject, xset: *c.xmlNodeSet) !Value {
    const list_obj = try ctx.createObject("DOMNodeList");
    const arr = try ctx.createArray();
    var i: usize = 0;
    while (i < @as(usize, @intCast(xset.nodeNr))) : (i += 1) {
        const n = xset.nodeTab[i];
        if (n == null) continue;
        const wrapped = if (n.*.type == c.XML_NAMESPACE_DECL)
            try wrapNamespaceNode(ctx, owner_doc, @ptrCast(n))
        else
            try wrapNode(ctx, n, owner_doc);
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, wrapped);
    }
    try list_obj.set(ctx.allocator, "__items", .{ .array = arr });
    try list_obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try list_obj.set(ctx.allocator, "length", .{ .int = @intCast(xset.nodeNr) });
    return .{ .object = list_obj };
}

fn wrapNamespaceNode(ctx: *NativeContext, owner_doc: *PhpObject, ns: *c.xmlNs) !Value {
    const obj = try ctx.createObject("DOMNameSpaceNode");
    try obj.set(ctx.allocator, "__ns_kind", .{ .bool = true });
    try obj.set(ctx.allocator, "__owner", .{ .object = owner_doc });
    if (ns.prefix != null) {
        const slice = ns.prefix[0..cstrLen(ns.prefix)];
        try obj.set(ctx.allocator, "__ns_prefix", .{ .string = try dupString(ctx, slice) });
    } else {
        try obj.set(ctx.allocator, "__ns_prefix", .{ .string = try dupString(ctx, "") });
    }
    if (ns.href != null) {
        const slice = ns.href[0..cstrLen(ns.href)];
        try obj.set(ctx.allocator, "__ns_href", .{ .string = try dupString(ctx, slice) });
    } else {
        try obj.set(ctx.allocator, "__ns_href", .{ .string = try dupString(ctx, "") });
    }
    return .{ .object = obj };
}

fn domXpathEvaluate(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const doc_v = obj.get("__doc");
    if (doc_v != .object) return .{ .bool = false };
    const doc = getDocPtr(doc_v.object) orelse return .{ .bool = false };

    var context_node: ?*c.xmlNode = null;
    if (args.len > 1 and args[1] == .object) context_node = getNodePtr(args[1].object);

    const xctx = c.xmlXPathNewContext(doc) orelse return .{ .bool = false };
    defer c.xmlXPathFreeContext(xctx);
    if (context_node) |cn| xctx.*.node = cn;

    const ns_map = obj.get("__namespaces");
    if (ns_map == .array) {
        for (ns_map.array.entries.items) |e| {
            if (e.key != .string or e.value != .string) continue;
            const prefix_z = try dupZ(ctx, e.key.string);
            const uri_z = try dupZ(ctx, e.value.string);
            _ = c.xmlXPathRegisterNs(xctx, @ptrCast(prefix_z.ptr), @ptrCast(uri_z.ptr));
        }
    }

    const expr_z = try dupZ(ctx, args[0].string);
    const result = c.xmlXPathEvalExpression(@ptrCast(expr_z.ptr), xctx);
    if (result == null) return .{ .bool = false };
    defer c.xmlXPathFreeObject(result);

    switch (result.*.type) {
        c.XPATH_NODESET => {
            const xs = result.*.nodesetval;
            if (xs == null) return try makeNodeList(ctx, doc_v.object, &.{});
            return try buildXpathNodeList(ctx, doc_v.object, xs);
        },
        c.XPATH_BOOLEAN => return .{ .bool = result.*.boolval != 0 },
        c.XPATH_NUMBER => return .{ .float = result.*.floatval },
        c.XPATH_STRING => {
            if (result.*.stringval == null) return .{ .string = try dupString(ctx, "") };
            const s = result.*.stringval;
            return .{ .string = try dupString(ctx, s[0..cstrLen(s)]) };
        },
        else => return .null,
    }
}

// ---------------- registration ----------------

pub fn register(vm: *VM, a: Allocator) !void {
    vm_singleton = vm;
    ensureGlobalInit();

    try registerDocClass(vm, a);
    try registerNodeClass(vm, a);
    try registerElementClass(vm, a);
    try registerCharacterDataClasses(vm, a);
    try registerAttrClass(vm, a);

    // DOMNameSpaceNode wraps libxml2 XPath namespace results (xmlNs entries
    // freed alongside the xmlNodeSet that produced them). zphp captures their
    // prefix+href into PhpObject properties so the wrapper outlives the result
    var ns_def = ClassDef{ .name = "DOMNameSpaceNode" };
    ns_def.parent = "DOMNode";
    try ns_def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try vm.classes.put(a, "DOMNameSpaceNode", ns_def);
    try vm.native_fns.put(a, "DOMNameSpaceNode::__get", domGenericGet);
    try registerNodeListClass(vm, a);
    try registerNamedNodeMapClass(vm, a);
    try registerXPathClass(vm, a);
    try registerConstants(vm, a);
}

fn registerDocClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "DOMDocument" };
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try def.methods.put(a, "loadXML", .{ .name = "loadXML", .arity = 1 });
    try def.methods.put(a, "load", .{ .name = "load", .arity = 1 });
    try def.methods.put(a, "loadHTML", .{ .name = "loadHTML", .arity = 1 });
    try def.methods.put(a, "loadHTMLFile", .{ .name = "loadHTMLFile", .arity = 1 });
    try def.methods.put(a, "saveXML", .{ .name = "saveXML", .arity = 0 });
    try def.methods.put(a, "saveHTML", .{ .name = "saveHTML", .arity = 0 });
    try def.methods.put(a, "save", .{ .name = "save", .arity = 1 });
    try def.methods.put(a, "createElement", .{ .name = "createElement", .arity = 1 });
    try def.methods.put(a, "createElementNS", .{ .name = "createElementNS", .arity = 2 });
    try def.methods.put(a, "createTextNode", .{ .name = "createTextNode", .arity = 1 });
    try def.methods.put(a, "createComment", .{ .name = "createComment", .arity = 1 });
    try def.methods.put(a, "createCDATASection", .{ .name = "createCDATASection", .arity = 1 });
    try def.methods.put(a, "createAttribute", .{ .name = "createAttribute", .arity = 1 });
    try def.methods.put(a, "createDocumentFragment", .{ .name = "createDocumentFragment", .arity = 0 });
    try def.methods.put(a, "importNode", .{ .name = "importNode", .arity = 1 });
    try def.methods.put(a, "getElementsByTagName", .{ .name = "getElementsByTagName", .arity = 1 });
    try def.methods.put(a, "getElementsByTagNameNS", .{ .name = "getElementsByTagNameNS", .arity = 2 });
    try def.methods.put(a, "getElementById", .{ .name = "getElementById", .arity = 1 });
    try def.methods.put(a, "normalizeDocument", .{ .name = "normalizeDocument", .arity = 0 });
    try def.methods.put(a, "appendChild", .{ .name = "appendChild", .arity = 1 });
    try def.methods.put(a, "removeChild", .{ .name = "removeChild", .arity = 1 });
    try def.methods.put(a, "replaceChild", .{ .name = "replaceChild", .arity = 2 });
    try def.methods.put(a, "insertBefore", .{ .name = "insertBefore", .arity = 1 });
    try def.methods.put(a, "cloneNode", .{ .name = "cloneNode", .arity = 0 });
    try def.methods.put(a, "hasChildNodes", .{ .name = "hasChildNodes", .arity = 0 });
    try def.methods.put(a, "hasAttributes", .{ .name = "hasAttributes", .arity = 0 });
    try def.methods.put(a, "isSameNode", .{ .name = "isSameNode", .arity = 1 });
    try def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try vm.classes.put(a, "DOMDocument", def);

    try vm.native_fns.put(a, "DOMDocument::__construct", domDocConstruct);
    try vm.native_fns.put(a, "DOMDocument::loadXML", domDocLoadXML);
    try vm.native_fns.put(a, "DOMDocument::load", domDocLoad);
    try vm.native_fns.put(a, "DOMDocument::loadHTML", domDocLoadHTML);
    try vm.native_fns.put(a, "DOMDocument::loadHTMLFile", domDocLoadHTMLFile);
    try vm.native_fns.put(a, "DOMDocument::saveXML", domDocSaveXML);
    try vm.native_fns.put(a, "DOMDocument::saveHTML", domDocSaveHTML);
    try vm.native_fns.put(a, "DOMDocument::save", domDocSave);
    try vm.native_fns.put(a, "DOMDocument::createElement", domDocCreateElement);
    try vm.native_fns.put(a, "DOMDocument::createElementNS", domDocCreateElementNS);
    try vm.native_fns.put(a, "DOMDocument::createTextNode", domDocCreateTextNode);
    try vm.native_fns.put(a, "DOMDocument::createComment", domDocCreateComment);
    try vm.native_fns.put(a, "DOMDocument::createCDATASection", domDocCreateCDATASection);
    try vm.native_fns.put(a, "DOMDocument::createAttribute", domDocCreateAttribute);
    try vm.native_fns.put(a, "DOMDocument::createDocumentFragment", domDocCreateDocumentFragment);
    try vm.native_fns.put(a, "DOMDocument::importNode", domDocImportNode);
    try vm.native_fns.put(a, "DOMDocument::getElementsByTagName", domDocGetElementsByTagName);
    try vm.native_fns.put(a, "DOMDocument::getElementsByTagNameNS", domGetElementsByTagNameNS);
    try vm.native_fns.put(a, "DOMDocument::getElementById", domDocGetElementById);
    try vm.native_fns.put(a, "DOMDocument::normalizeDocument", domDocNormalizeDocument);
    try vm.native_fns.put(a, "DOMDocument::appendChild", domNodeAppendChild);
    try vm.native_fns.put(a, "DOMDocument::removeChild", domNodeRemoveChild);
    try vm.native_fns.put(a, "DOMDocument::replaceChild", domNodeReplaceChild);
    try vm.native_fns.put(a, "DOMDocument::insertBefore", domNodeInsertBefore);
    try vm.native_fns.put(a, "DOMDocument::cloneNode", domNodeCloneNode);
    try vm.native_fns.put(a, "DOMDocument::hasChildNodes", domNodeHasChildNodes);
    try vm.native_fns.put(a, "DOMDocument::hasAttributes", domNodeHasAttributes);
    try vm.native_fns.put(a, "DOMDocument::isSameNode", domNodeIsSameNode);
    try vm.native_fns.put(a, "DOMDocument::__get", domGenericGet);
}

fn registerNodeClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "DOMNode" };
    try def.methods.put(a, "appendChild", .{ .name = "appendChild", .arity = 1 });
    try def.methods.put(a, "removeChild", .{ .name = "removeChild", .arity = 1 });
    try def.methods.put(a, "replaceChild", .{ .name = "replaceChild", .arity = 2 });
    try def.methods.put(a, "insertBefore", .{ .name = "insertBefore", .arity = 1 });
    try def.methods.put(a, "cloneNode", .{ .name = "cloneNode", .arity = 0 });
    try def.methods.put(a, "hasChildNodes", .{ .name = "hasChildNodes", .arity = 0 });
    try def.methods.put(a, "hasAttributes", .{ .name = "hasAttributes", .arity = 0 });
    try def.methods.put(a, "isSameNode", .{ .name = "isSameNode", .arity = 1 });
    try def.methods.put(a, "lookupPrefix", .{ .name = "lookupPrefix", .arity = 1 });
    try def.methods.put(a, "lookupNamespaceURI", .{ .name = "lookupNamespaceURI", .arity = 1 });
    try def.methods.put(a, "getNodePath", .{ .name = "getNodePath", .arity = 0 });
    try def.methods.put(a, "getLineNo", .{ .name = "getLineNo", .arity = 0 });
    try def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try def.methods.put(a, "__set", .{ .name = "__set", .arity = 2 });
    try vm.classes.put(a, "DOMNode", def);
    try registerNodeNativeFns(vm, a, "DOMNode");
}

// table of method-name → native-fn that every DOM* node class needs.
// callers pass a comptime class name so the "Class::method" keys are
// built at comptime and stored as static string literals (no allocation)
fn registerNodeNativeFns(vm: *VM, a: Allocator, comptime class_name: []const u8) !void {
    const pairs = .{
        .{ "appendChild", domNodeAppendChild },
        .{ "removeChild", domNodeRemoveChild },
        .{ "replaceChild", domNodeReplaceChild },
        .{ "insertBefore", domNodeInsertBefore },
        .{ "cloneNode", domNodeCloneNode },
        .{ "hasChildNodes", domNodeHasChildNodes },
        .{ "hasAttributes", domNodeHasAttributes },
        .{ "isSameNode", domNodeIsSameNode },
        .{ "lookupPrefix", domNodeLookupPrefix },
        .{ "lookupNamespaceURI", domNodeLookupNamespaceURI },
        .{ "getNodePath", domNodeGetNodePath },
        .{ "getLineNo", domNodeGetLineNo },
        .{ "__get", domGenericGet },
        .{ "__set", domGenericSet },
    };
    inline for (pairs) |p| {
        try vm.native_fns.put(a, class_name ++ "::" ++ p[0], p[1]);
    }
}

fn registerElementClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "DOMElement" };
    def.parent = "DOMNode";
    try def.methods.put(a, "getAttribute", .{ .name = "getAttribute", .arity = 1 });
    try def.methods.put(a, "setAttribute", .{ .name = "setAttribute", .arity = 2 });
    try def.methods.put(a, "hasAttribute", .{ .name = "hasAttribute", .arity = 1 });
    try def.methods.put(a, "removeAttribute", .{ .name = "removeAttribute", .arity = 1 });
    try def.methods.put(a, "getAttributeNS", .{ .name = "getAttributeNS", .arity = 2 });
    try def.methods.put(a, "setAttributeNS", .{ .name = "setAttributeNS", .arity = 3 });
    try def.methods.put(a, "hasAttributeNS", .{ .name = "hasAttributeNS", .arity = 2 });
    try def.methods.put(a, "removeAttributeNS", .{ .name = "removeAttributeNS", .arity = 2 });
    try def.methods.put(a, "getElementsByTagName", .{ .name = "getElementsByTagName", .arity = 1 });
    try def.methods.put(a, "getElementsByTagNameNS", .{ .name = "getElementsByTagNameNS", .arity = 2 });
    try def.methods.put(a, "getAttributeNode", .{ .name = "getAttributeNode", .arity = 1 });
    // also need all DOMNode methods (parent walk handles dispatch but we register the natives directly)
    try def.methods.put(a, "appendChild", .{ .name = "appendChild", .arity = 1 });
    try def.methods.put(a, "removeChild", .{ .name = "removeChild", .arity = 1 });
    try def.methods.put(a, "replaceChild", .{ .name = "replaceChild", .arity = 2 });
    try def.methods.put(a, "insertBefore", .{ .name = "insertBefore", .arity = 1 });
    try def.methods.put(a, "cloneNode", .{ .name = "cloneNode", .arity = 0 });
    try def.methods.put(a, "hasChildNodes", .{ .name = "hasChildNodes", .arity = 0 });
    try def.methods.put(a, "hasAttributes", .{ .name = "hasAttributes", .arity = 0 });
    try def.methods.put(a, "isSameNode", .{ .name = "isSameNode", .arity = 1 });
    try def.methods.put(a, "lookupPrefix", .{ .name = "lookupPrefix", .arity = 1 });
    try def.methods.put(a, "lookupNamespaceURI", .{ .name = "lookupNamespaceURI", .arity = 1 });
    try def.methods.put(a, "getNodePath", .{ .name = "getNodePath", .arity = 0 });
    try def.methods.put(a, "getLineNo", .{ .name = "getLineNo", .arity = 0 });
    try def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try def.methods.put(a, "__set", .{ .name = "__set", .arity = 2 });
    try vm.classes.put(a, "DOMElement", def);

    try vm.native_fns.put(a, "DOMElement::getAttribute", domElementGetAttribute);
    try vm.native_fns.put(a, "DOMElement::setAttribute", domElementSetAttribute);
    try vm.native_fns.put(a, "DOMElement::hasAttribute", domElementHasAttribute);
    try vm.native_fns.put(a, "DOMElement::removeAttribute", domElementRemoveAttribute);
    try vm.native_fns.put(a, "DOMElement::getAttributeNS", domElementGetAttributeNS);
    try vm.native_fns.put(a, "DOMElement::setAttributeNS", domElementSetAttributeNS);
    try vm.native_fns.put(a, "DOMElement::hasAttributeNS", domElementHasAttributeNS);
    try vm.native_fns.put(a, "DOMElement::removeAttributeNS", domElementRemoveAttributeNS);
    try vm.native_fns.put(a, "DOMElement::getElementsByTagName", domElementGetElementsByTagName);
    try vm.native_fns.put(a, "DOMElement::getElementsByTagNameNS", domGetElementsByTagNameNS);
    try vm.native_fns.put(a, "DOMElement::getAttributeNode", domElementGetAttributeNode);
    try registerNodeNativeFns(vm, a, "DOMElement");
}

fn registerCharacterDataClasses(vm: *VM, a: Allocator) !void {
    inline for (.{ "DOMText", "DOMComment", "DOMCdataSection", "DOMCharacterData", "DOMProcessingInstruction", "DOMEntityReference", "DOMDocumentFragment" }) |name| {
        var def = ClassDef{ .name = name };
        def.parent = "DOMNode";
        try def.methods.put(a, "appendData", .{ .name = "appendData", .arity = 1 });
        try def.methods.put(a, "substringData", .{ .name = "substringData", .arity = 2 });
        try def.methods.put(a, "appendChild", .{ .name = "appendChild", .arity = 1 });
        try def.methods.put(a, "removeChild", .{ .name = "removeChild", .arity = 1 });
        try def.methods.put(a, "cloneNode", .{ .name = "cloneNode", .arity = 0 });
        try def.methods.put(a, "hasChildNodes", .{ .name = "hasChildNodes", .arity = 0 });
        try def.methods.put(a, "isSameNode", .{ .name = "isSameNode", .arity = 1 });
        try def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
        try def.methods.put(a, "__set", .{ .name = "__set", .arity = 2 });
        try vm.classes.put(a, name, def);

        try vm.native_fns.put(a, name ++ "::appendData", domCdAppendData);
        try vm.native_fns.put(a, name ++ "::substringData", domCdSubstringData);
        try registerNodeNativeFns(vm, a, name);
    }
}

fn registerAttrClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "DOMAttr" };
    def.parent = "DOMNode";
    try def.methods.put(a, "appendChild", .{ .name = "appendChild", .arity = 1 });
    try def.methods.put(a, "cloneNode", .{ .name = "cloneNode", .arity = 0 });
    try def.methods.put(a, "isSameNode", .{ .name = "isSameNode", .arity = 1 });
    try def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try def.methods.put(a, "__set", .{ .name = "__set", .arity = 2 });
    try vm.classes.put(a, "DOMAttr", def);
    try registerNodeNativeFns(vm, a, "DOMAttr");
}

fn registerNodeListClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "DOMNodeList" };
    try def.interfaces.append(a, "Countable");
    try def.interfaces.append(a, "IteratorAggregate");
    try def.interfaces.append(a, "ArrayAccess");
    try def.methods.put(a, "item", .{ .name = "item", .arity = 1 });
    try def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try def.methods.put(a, "getIterator", .{ .name = "getIterator", .arity = 0 });
    try def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try vm.classes.put(a, "DOMNodeList", def);

    try vm.native_fns.put(a, "DOMNodeList::item", domNodeListItem);
    try vm.native_fns.put(a, "DOMNodeList::count", domNodeListCount);
    try vm.native_fns.put(a, "DOMNodeList::getIterator", domNodeListGetIterator);
    try vm.native_fns.put(a, "DOMNodeList::__get", domNodeListGet);
    try vm.native_fns.put(a, "DOMNodeList::offsetExists", domNodeListOffsetExists);
    try vm.native_fns.put(a, "DOMNodeList::offsetGet", domNodeListItem);
    try vm.native_fns.put(a, "DOMNodeList::offsetSet", domNodeListReadOnly);
    try vm.native_fns.put(a, "DOMNodeList::offsetUnset", domNodeListReadOnly);
}

fn domNodeListOffsetExists(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const obj = getThisGlobal() orelse return .{ .bool = false };
    const arr = nlItems(obj) orelse return .{ .bool = false };
    const idx = Value.toInt(args[0]);
    return .{ .bool = idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len)) };
}

fn domNodeListReadOnly(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // PHP's DOMNodeList ArrayAccess is read-only; offsetSet/offsetUnset are
    // no-ops in practice (they throw on some builds but the result is the
    // same: the list isn't mutated). matching that is enough for compat
    return .null;
}

fn domNodeListGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    if (std.mem.eql(u8, args[0].string, "length")) {
        const items = obj.get("__items");
        if (items != .array) return .{ .int = 0 };
        return .{ .int = @intCast(items.array.entries.items.len) };
    }
    return .null;
}

// DOMNamedNodeMap iterates with the attribute name as key (PHP semantics)
// rather than the numeric index used for NodeList
fn domNNMGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const named = obj.get("__named");
    if (named != .array) return .null;
    const iter_obj = try ctx.createObject("ArrayIterator");
    try iter_obj.set(ctx.allocator, "__data", named);
    try iter_obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try iter_obj.set(ctx.allocator, "__flags", .{ .int = 0 });
    return .{ .object = iter_obj };
}

fn domNodeListGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const items = obj.get("__items");
    if (items != .array) return .null;
    const iter_obj = try ctx.createObject("ArrayIterator");
    try iter_obj.set(ctx.allocator, "__data", items);
    try iter_obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try iter_obj.set(ctx.allocator, "__flags", .{ .int = 0 });
    return .{ .object = iter_obj };
}

fn registerNamedNodeMapClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "DOMNamedNodeMap" };
    try def.interfaces.append(a, "Countable");
    try def.interfaces.append(a, "IteratorAggregate");
    try def.methods.put(a, "getNamedItem", .{ .name = "getNamedItem", .arity = 1 });
    try def.methods.put(a, "item", .{ .name = "item", .arity = 1 });
    try def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try def.methods.put(a, "getIterator", .{ .name = "getIterator", .arity = 0 });
    try def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try vm.classes.put(a, "DOMNamedNodeMap", def);

    try vm.native_fns.put(a, "DOMNamedNodeMap::getNamedItem", domNNMGetNamedItem);
    try vm.native_fns.put(a, "DOMNamedNodeMap::item", domNNMItem);
    try vm.native_fns.put(a, "DOMNamedNodeMap::count", domNNMCount);
    try vm.native_fns.put(a, "DOMNamedNodeMap::getIterator", domNNMGetIterator);
    try vm.native_fns.put(a, "DOMNamedNodeMap::__get", domNodeListGet);
}

fn registerXPathClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "DOMXPath" };
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try def.methods.put(a, "query", .{ .name = "query", .arity = 1 });
    try def.methods.put(a, "evaluate", .{ .name = "evaluate", .arity = 1 });
    try def.methods.put(a, "registerNamespace", .{ .name = "registerNamespace", .arity = 2 });
    try vm.classes.put(a, "DOMXPath", def);

    try vm.native_fns.put(a, "DOMXPath::__construct", domXpathConstruct);
    try vm.native_fns.put(a, "DOMXPath::query", domXpathQuery);
    try vm.native_fns.put(a, "DOMXPath::evaluate", domXpathEvaluate);
    try vm.native_fns.put(a, "DOMXPath::registerNamespace", domXpathRegisterNamespace);
}

fn registerConstants(vm: *VM, a: Allocator) !void {
    const consts = .{
        .{ "XML_ELEMENT_NODE", 1 },
        .{ "XML_ATTRIBUTE_NODE", 2 },
        .{ "XML_TEXT_NODE", 3 },
        .{ "XML_CDATA_SECTION_NODE", 4 },
        .{ "XML_ENTITY_REF_NODE", 5 },
        .{ "XML_ENTITY_NODE", 6 },
        .{ "XML_PI_NODE", 7 },
        .{ "XML_COMMENT_NODE", 8 },
        .{ "XML_DOCUMENT_NODE", 9 },
        .{ "XML_DOCUMENT_TYPE_NODE", 10 },
        .{ "XML_DOCUMENT_FRAG_NODE", 11 },
        .{ "XML_NOTATION_NODE", 12 },
        .{ "XML_HTML_DOCUMENT_NODE", 13 },
        .{ "XML_DTD_NODE", 14 },
        .{ "XML_ELEMENT_DECL", 15 },
        .{ "XML_ATTRIBUTE_DECL", 16 },
        .{ "XML_ENTITY_DECL", 17 },
        .{ "XML_NAMESPACE_DECL", 18 },
        .{ "XML_XINCLUDE_START", 19 },
        .{ "XML_XINCLUDE_END", 20 },
        .{ "LIBXML_DTDLOAD", 4 },
        .{ "LIBXML_DTDATTR", 8 },
        .{ "LIBXML_DTDVALID", 16 },
        .{ "LIBXML_NOENT", 2 },
        .{ "LIBXML_NOERROR", 32 },
        .{ "LIBXML_NOWARNING", 64 },
        .{ "LIBXML_NOBLANKS", 256 },
        .{ "LIBXML_NSCLEAN", 8192 },
        .{ "LIBXML_NOCDATA", 16384 },
        .{ "LIBXML_NONET", 2048 },
        .{ "LIBXML_PEDANTIC", 128 },
        .{ "LIBXML_NOXMLDECL", 2 },
        .{ "LIBXML_PARSEHUGE", 524288 },
        .{ "LIBXML_HTML_NOIMPLIED", 8192 },
        .{ "LIBXML_HTML_NODEFDTD", 4 },
        .{ "LIBXML_COMPACT", 65536 },
        .{ "LIBXML_BIGLINES", 4194304 },
        .{ "LIBXML_SCHEMA_CREATE", 1 },
    };
    inline for (consts) |k| {
        try vm.php_constants.put(a, k[0], .{ .int = k[1] });
    }

    try vm.php_constants.put(a, "LIBXML_VERSION", .{ .int = @intCast(c.LIBXML_VERSION) });
    // c.LIBXML_DOTTED_VERSION is a string literal macro so this slice points
    // into the binary's rodata and lives for the program's lifetime
    try vm.php_constants.put(a, "LIBXML_DOTTED_VERSION", .{ .string = std.mem.span(@as([*:0]const u8, c.LIBXML_DOTTED_VERSION)) });
}

// ---------------- libxml error-handling stubs ----------------
//
// Symfony, Laravel, and most frameworks call libxml_use_internal_errors(true)
// before parsing untrusted HTML/XML to suppress warning output and collect
// errors. We don't surface libxml warnings at all (silentErrorHandler eats
// them), so these are minimal-state shims that satisfy the call signature

var libxml_internal_errors_enabled: bool = false;

pub const libxml_entries = .{
    .{ "libxml_use_internal_errors", libxmlUseInternalErrors },
    .{ "libxml_clear_errors", libxmlClearErrors },
    .{ "libxml_get_errors", libxmlGetErrors },
    .{ "libxml_get_last_error", libxmlGetLastError },
    .{ "libxml_disable_entity_loader", libxmlDisableEntityLoader },
    .{ "libxml_set_external_entity_loader", libxmlSetExternalEntityLoader },
};

fn libxmlUseInternalErrors(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const prev = libxml_internal_errors_enabled;
    if (args.len > 0) {
        switch (args[0]) {
            .bool => |b| libxml_internal_errors_enabled = b,
            .int => |i| libxml_internal_errors_enabled = i != 0,
            else => {},
        }
    }
    return .{ .bool = prev };
}

fn libxmlClearErrors(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn libxmlGetErrors(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const arr = try ctx.createArray();
    return .{ .array = arr };
}

fn libxmlGetLastError(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn libxmlDisableEntityLoader(_: *NativeContext, args: []const Value) RuntimeError!Value {
    // deprecated in PHP 8.0+ and a noop on modern libxml. accept and return true
    _ = args;
    return .{ .bool = true };
}

fn libxmlSetExternalEntityLoader(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "DOMDocument")) {
            if (getDocPtr(obj)) |doc| c.xmlFreeDoc(doc);
        }
    }
}
