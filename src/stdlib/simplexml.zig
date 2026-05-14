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

const c = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
    @cInclude("libxml/xpath.h");
    @cInclude("libxml/xpathInternals.h");
});

// SimpleXMLElement wraps a single xmlNodePtr plus tracking state for the
// "sibling set" semantics PHP exposes - $root->item is a wrapper around the
// first <item>, but iterating it walks all <item> siblings under $root
//
// state stored on the PhpObject:
//   __node  : xmlNodePtr (the current element)
//   __doc   : xmlDocPtr (owning document, freed at request end via dom.zig)
//   __ns    : optional default namespace filter (URI)
//   __is_attr : bool - this wrapper represents an attribute pseudo-element
//   __attr_name : when __is_attr, the attribute's name

pub const entries = .{
    .{ "simplexml_load_string", sxmlLoadString },
    .{ "simplexml_load_file", sxmlLoadFile },
    .{ "simplexml_import_dom", sxmlImportDom },
};

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

fn getNodePtr(obj: *const PhpObject) ?*c.xmlNode {
    const v = obj.get("__node");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn getDocPtr(obj: *const PhpObject) ?*c.xmlDoc {
    const v = obj.get("__doc");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn buildWrapper(ctx: *NativeContext, doc: *c.xmlDoc, node: *c.xmlNode) !*PhpObject {
    return buildWrapperMode(ctx, doc, node, .siblings);
}

fn buildRootWrapper(ctx: *NativeContext, doc: *c.xmlDoc, node: *c.xmlNode) !*PhpObject {
    return buildWrapperMode(ctx, doc, node, .children);
}

const IterMode = enum { siblings, children };

fn buildWrapperMode(ctx: *NativeContext, doc: *c.xmlDoc, node: *c.xmlNode, mode: IterMode) !*PhpObject {
    const obj = try ctx.createObject("SimpleXMLElement");
    try obj.set(ctx.allocator, "__node", .{ .int = @intCast(@intFromPtr(node)) });
    try obj.set(ctx.allocator, "__doc", .{ .int = @intCast(@intFromPtr(doc)) });
    try obj.set(ctx.allocator, "__is_attr", .{ .bool = false });
    try obj.set(ctx.allocator, "__iter_children", .{ .bool = mode == .children });
    return obj;
}

fn buildAttrWrapper(ctx: *NativeContext, doc: *c.xmlDoc, owner: *c.xmlNode, attr_name: []const u8) !*PhpObject {
    const obj = try ctx.createObject("SimpleXMLElement");
    try obj.set(ctx.allocator, "__node", .{ .int = @intCast(@intFromPtr(owner)) });
    try obj.set(ctx.allocator, "__doc", .{ .int = @intCast(@intFromPtr(doc)) });
    try obj.set(ctx.allocator, "__is_attr", .{ .bool = true });
    try obj.set(ctx.allocator, "__attr_name", .{ .string = try dupString(ctx, attr_name) });
    return obj;
}

fn nodeContent(ctx: *NativeContext, node: *c.xmlNode) ![]const u8 {
    const content = c.xmlNodeGetContent(node);
    if (content == null) return "";
    defer c.xmlFree.?(content);
    return try dupString(ctx, content[0..cstrLen(content)]);
}

fn nameMatches(n: *c.xmlNode, name: []const u8) bool {
    if (n.type != c.XML_ELEMENT_NODE) return false;
    if (n.name == null) return false;
    return std.mem.eql(u8, n.name[0..cstrLen(n.name)], name);
}

// json_encode integration: walk a SimpleXMLElement's underlying xml tree and
// return a Value matching what PHP's json_encode produces for SimpleXMLElement.
// rules: a leaf element with only text returns the text as a string; an element
// with children returns an associative array keyed by child name (siblings with
// the same name group into a numerically-keyed array); attributes are exposed
// under "@attributes"
pub fn elementToJsonValue(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    const node = getNodePtr(obj) orelse return .null;
    if (obj.get("__is_attr") == .bool and obj.get("__is_attr").bool) {
        const an = obj.get("__attr_name");
        if (an != .string) return .null;
        const name_z = try dupZ(ctx, an.string);
        const v = c.xmlGetProp(node, name_z.ptr);
        if (v == null) return .{ .string = "" };
        defer c.xmlFree.?(v);
        return .{ .string = try dupString(ctx, v[0..cstrLen(v)]) };
    }
    return try nodeToJsonValue(ctx, node);
}

fn nodeToJsonValue(ctx: *NativeContext, node: *c.xmlNode) RuntimeError!Value {
    var has_attr = false;
    var attr_iter: ?*c.xmlAttr = @ptrCast(node.properties);
    while (attr_iter) |_| : (attr_iter = @ptrCast(attr_iter.?.next)) {
        has_attr = true;
        break;
    }

    var has_elem_child = false;
    var ch: ?*c.xmlNode = @ptrCast(node.children);
    while (ch) |cn| : (ch = @ptrCast(cn.next)) {
        if (cn.type == c.XML_ELEMENT_NODE) { has_elem_child = true; break; }
    }

    // PHP's json_encode on SimpleXMLElement mirrors the iterator: if the
    // element has direct text content, that text is the value (attributes and
    // children are ignored). this matches `(string)$elem` semantics
    var has_text = false;
    ch = @ptrCast(node.children);
    while (ch) |cn| : (ch = @ptrCast(cn.next)) {
        if (cn.type == c.XML_TEXT_NODE or cn.type == c.XML_CDATA_SECTION_NODE) {
            const txt = c.xmlNodeGetContent(cn);
            if (txt != null) {
                defer c.xmlFree.?(txt);
                if (cstrLen(txt) > 0) { has_text = true; break; }
            }
        }
    }

    if (has_text) {
        // direct text children only; xmlNodeGetContent would recurse into
        // child elements which PHP does not include here
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(ctx.allocator);
        var tch: ?*c.xmlNode = @ptrCast(node.children);
        while (tch) |cn| : (tch = @ptrCast(cn.next)) {
            if (cn.type == c.XML_TEXT_NODE or cn.type == c.XML_CDATA_SECTION_NODE) {
                const txt = c.xmlNodeGetContent(cn);
                if (txt != null) {
                    defer c.xmlFree.?(txt);
                    try buf.appendSlice(ctx.allocator, txt[0..cstrLen(txt)]);
                }
            }
        }
        return .{ .string = try dupString(ctx, buf.items) };
    }

    if (!has_attr and !has_elem_child) {
        // empty element: PHP returns an empty object, not an empty list. give
        // back a stdClass so json_encode renders `{}`
        const obj = try ctx.allocator.create(PhpObject);
        obj.* = .{ .class_name = "stdClass" };
        try ctx.vm.objects.append(ctx.allocator, obj);
        return .{ .object = obj };
    }

    const result = try ctx.allocator.create(PhpArray);
    result.* = .{};
    try ctx.vm.arrays.append(ctx.allocator, result);

    if (has_attr) {
        const attrs = try ctx.allocator.create(PhpArray);
        attrs.* = .{};
        try ctx.vm.arrays.append(ctx.allocator, attrs);
        attr_iter = @ptrCast(node.properties);
        while (attr_iter) |a| : (attr_iter = @ptrCast(a.next)) {
            if (a.name == null) continue;
            const aname = try dupString(ctx, a.name[0..cstrLen(a.name)]);
            const an_z = try ctx.allocator.allocSentinel(u8, aname.len, 0);
            @memcpy(an_z[0..aname.len], aname);
            defer ctx.allocator.free(an_z);
            const v = c.xmlGetProp(node, an_z.ptr);
            if (v == null) {
                try attrs.set(ctx.allocator, .{ .string = aname }, .{ .string = "" });
            } else {
                defer c.xmlFree.?(v);
                const vs = try dupString(ctx, v[0..cstrLen(v)]);
                try attrs.set(ctx.allocator, .{ .string = aname }, .{ .string = vs });
            }
        }
        try result.set(ctx.allocator, .{ .string = "@attributes" }, .{ .array = attrs });
    }

    // walk children, grouping by element name
    ch = @ptrCast(node.children);
    while (ch) |cn| : (ch = @ptrCast(cn.next)) {
        if (cn.type != c.XML_ELEMENT_NODE) continue;
        if (cn.name == null) continue;
        const cname = try dupString(ctx, cn.name[0..cstrLen(cn.name)]);
        const child_val = try nodeToJsonValue(ctx, cn);
        const existing = result.get(.{ .string = cname });
        if (existing == .null) {
            try result.set(ctx.allocator, .{ .string = cname }, child_val);
        } else if (existing == .array and isSequentialList(existing.array)) {
            try existing.array.append(ctx.allocator, child_val);
        } else {
            // promote single value into a 2-element list
            const list = try ctx.allocator.create(PhpArray);
            list.* = .{};
            try ctx.vm.arrays.append(ctx.allocator, list);
            try list.append(ctx.allocator, existing);
            try list.append(ctx.allocator, child_val);
            try result.set(ctx.allocator, .{ .string = cname }, .{ .array = list });
        }
    }
    return .{ .array = result };
}

fn isSequentialList(arr: *const PhpArray) bool {
    for (arr.entries.items, 0..) |e, i| {
        if (e.key != .int or e.key.int != @as(i64, @intCast(i))) return false;
    }
    return true;
}

// ---------------- top-level functions ----------------

fn sxmlLoadString(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const src = args[0].string;
    var opts: c_int = 0;
    if (args.len > 2 and args[2] == .int) opts = @intCast(args[2].int);
    const doc = c.xmlReadMemory(src.ptr, @intCast(src.len), null, null, opts) orelse return .{ .bool = false };
    const root = c.xmlDocGetRootElement(doc) orelse {
        c.xmlFreeDoc(doc);
        return .{ .bool = false };
    };
    const wrapper = try buildRootWrapper(ctx, doc, root);
    try wrapper.set(ctx.allocator, "__owns_doc", .{ .bool = true });
    return .{ .object = wrapper };
}

fn sxmlLoadFile(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const path_z = try dupZ(ctx, args[0].string);
    var opts: c_int = 0;
    if (args.len > 2 and args[2] == .int) opts = @intCast(args[2].int);
    const doc = c.xmlReadFile(path_z.ptr, null, opts) orelse return .{ .bool = false };
    const root = c.xmlDocGetRootElement(doc) orelse {
        c.xmlFreeDoc(doc);
        return .{ .bool = false };
    };
    const wrapper = try buildRootWrapper(ctx, doc, root);
    try wrapper.set(ctx.allocator, "__owns_doc", .{ .bool = true });
    return .{ .object = wrapper };
}

fn sxmlImportDom(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .null;
    const dom_obj = args[0].object;
    // DOM objects store xmlNodePtr in "__node" via dom.zig - reuse that
    const node_v = dom_obj.get("__node");
    if (node_v != .int or node_v.int == 0) return .null;
    const node: *c.xmlNode = @ptrFromInt(@as(usize, @intCast(node_v.int)));
    // for a DOMDocument, descend to root; for any node, use it
    const target: *c.xmlNode = if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE)
        c.xmlDocGetRootElement(@ptrCast(node)) orelse return .null
    else
        node;
    const doc = target.doc orelse return .null;
    const wrapper = try buildWrapper(ctx, doc, target);
    return .{ .object = wrapper };
}

// ---------------- SimpleXMLElement::__construct ----------------

fn sxmlConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const src = args[0].string;
    var opts: c_int = 0;
    if (args.len > 1 and args[1] == .int) opts = @intCast(args[1].int);
    var is_url: bool = false;
    if (args.len > 2 and args[2] == .bool) is_url = args[2].bool;

    const doc = if (is_url) blk: {
        const path_z = try dupZ(ctx, src);
        break :blk c.xmlReadFile(path_z.ptr, null, opts);
    } else c.xmlReadMemory(src.ptr, @intCast(src.len), null, null, opts);
    if (doc == null) return .null;

    const root = c.xmlDocGetRootElement(doc) orelse {
        c.xmlFreeDoc(doc);
        return .null;
    };
    try obj.set(ctx.allocator, "__node", .{ .int = @intCast(@intFromPtr(root)) });
    try obj.set(ctx.allocator, "__doc", .{ .int = @intCast(@intFromPtr(doc)) });
    try obj.set(ctx.allocator, "__owns_doc", .{ .bool = true });
    try obj.set(ctx.allocator, "__is_attr", .{ .bool = false });
    try obj.set(ctx.allocator, "__iter_children", .{ .bool = true });
    return .null;
}

// ---------------- methods ----------------

fn sxmlGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (obj.get("__is_attr") == .bool and obj.get("__is_attr").bool) {
        const an = obj.get("__attr_name");
        if (an == .string) return an;
    }
    const node = getNodePtr(obj) orelse return .null;
    if (node.name == null) return .null;
    return .{ .string = try dupString(ctx, node.name[0..cstrLen(node.name)]) };
}

fn sxmlAsXML(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };

    if (args.len > 0 and args[0] == .string) {
        const path_z = try dupZ(ctx, args[0].string);
        const written = c.xmlSaveFormatFile(path_z.ptr, doc, 0);
        return .{ .bool = written >= 0 };
    }

    // is this the root element? PHP returns full doc XML; otherwise just node fragment
    const root = c.xmlDocGetRootElement(doc);
    if (root != null and root == node) {
        var out: [*c]u8 = null;
        var size: c_int = 0;
        c.xmlDocDumpFormatMemoryEnc(doc, &out, &size, doc.*.encoding, 0);
        if (out == null) return .{ .bool = false };
        defer c.xmlFree.?(out);
        return .{ .string = try dupString(ctx, out[0..@intCast(size)]) };
    }

    const buf = c.xmlBufferCreate();
    defer c.xmlBufferFree(buf);
    _ = c.xmlNodeDump(buf, doc, node, 0, 0);
    const content = c.xmlBufferContent(buf);
    if (content == null) return .{ .string = try dupString(ctx, "") };
    return .{ .string = try dupString(ctx, content[0..cstrLen(content)]) };
}

fn sxmlSaveXML(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return sxmlAsXML(ctx, args);
}

fn sxmlCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    const node = getNodePtr(obj) orelse return .{ .int = 0 };
    // count matches iteration: children-mode counts child elements; sibling-mode
    // counts same-named siblings of $this; attr-view counts attributes
    if (obj.get("__attr_view") == .bool and obj.get("__attr_view").bool) {
        var count: i64 = 0;
        var attr = node.properties;
        while (attr != null) : (attr = attr.*.next) count += 1;
        return .{ .int = count };
    }
    if (obj.get("__iter_children") == .bool and obj.get("__iter_children").bool) {
        var count: i64 = 0;
        var child = node.children;
        while (child != null) : (child = child.*.next) {
            if (child.*.type == c.XML_ELEMENT_NODE) count += 1;
        }
        return .{ .int = count };
    }
    if (node.name == null) return .{ .int = 0 };
    const self_name = node.name[0..cstrLen(node.name)];
    var count: i64 = 0;
    var ch: ?*c.xmlNode = node;
    while (ch != null) : (ch = ch.?.next) {
        const cn = ch.?;
        if (cn.type != c.XML_ELEMENT_NODE) continue;
        if (cn.name == null) continue;
        if (std.mem.eql(u8, cn.name[0..cstrLen(cn.name)], self_name)) count += 1;
    }
    return .{ .int = count };
}

fn sxmlChildren(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const doc = getDocPtr(obj) orelse return .null;
    // ->children() must yield the node's CHILDREN, not iterate same-named
    // siblings of the node itself - that's the default sibling-mode wrapper
    const wrapper = try buildWrapperMode(ctx, doc, node, .children);
    // optional namespace filter. PHP: children(string $ns = null, bool $isPrefix = false)
    if (args.len >= 1 and args[0] == .string and args[0].string.len > 0) {
        const ns_or_prefix = args[0].string;
        const is_prefix = args.len >= 2 and args[1] == .bool and args[1].bool;
        var resolved_ns: []const u8 = ns_or_prefix;
        if (is_prefix) {
            // resolve prefix to URI via the document's namespace map
            const prefix_z = try dupZ(ctx, ns_or_prefix);
            const ns = c.xmlSearchNs(doc, node, @ptrCast(prefix_z.ptr));
            if (ns != null and ns.*.href != null) {
                const href = ns.*.href;
                resolved_ns = href[0..cstrLen(href)];
            }
        }
        const owned = try ctx.allocator.dupe(u8, resolved_ns);
        try ctx.strings.append(ctx.allocator, owned);
        try wrapper.set(ctx.allocator, "__ns", .{ .string = owned });
    }
    return .{ .object = wrapper };
}

fn sxmlAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    _ = args;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const doc = getDocPtr(obj) orelse return .null;
    // return a SimpleXMLElement-like wrapper exposing attributes via offsetGet/iteration.
    // store as a special wrapper with __attr_view = true
    const wrapper = try ctx.createObject("SimpleXMLElement");
    try wrapper.set(ctx.allocator, "__node", .{ .int = @intCast(@intFromPtr(node)) });
    try wrapper.set(ctx.allocator, "__doc", .{ .int = @intCast(@intFromPtr(doc)) });
    try wrapper.set(ctx.allocator, "__is_attr", .{ .bool = false });
    try wrapper.set(ctx.allocator, "__attr_view", .{ .bool = true });
    return .{ .object = wrapper };
}

fn sxmlXpath(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const doc = getDocPtr(obj) orelse return .{ .bool = false };

    const xctx = c.xmlXPathNewContext(doc) orelse return .{ .bool = false };
    defer c.xmlXPathFreeContext(xctx);
    xctx.*.node = node;

    // register any namespaces stored on this wrapper
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

    const arr = try ctx.createArray();
    if (result.*.type == c.XPATH_NODESET and result.*.nodesetval != null) {
        const ns = result.*.nodesetval;
        var i: usize = 0;
        while (i < @as(usize, @intCast(ns.*.nodeNr))) : (i += 1) {
            const n = ns.*.nodeTab[i];
            if (n == null) continue;
            const wrapper = try buildWrapper(ctx, doc, n);
            try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .object = wrapper });
        }
    }
    return .{ .array = arr };
}

fn sxmlRegisterXPathNamespace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
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

fn sxmlAddChild(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const doc = getDocPtr(obj) orelse return .null;
    const name_z = try dupZ(ctx, args[0].string);
    const content_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string) try dupZ(ctx, args[1].string) else null;
    const ns_z: ?[:0]u8 = if (args.len > 2 and args[2] == .string and args[2].string.len > 0) try dupZ(ctx, args[2].string) else null;

    var ns_ptr: ?*c.xmlNs = null;
    if (ns_z) |nz| {
        ns_ptr = c.xmlSearchNsByHref(doc, node, @ptrCast(nz.ptr));
        if (ns_ptr == null) ns_ptr = c.xmlNewNs(node, @ptrCast(nz.ptr), null);
    }
    const content_ptr: [*c]const u8 = if (content_z) |cz| @ptrCast(cz.ptr) else null;
    const child = c.xmlNewTextChild(node, ns_ptr, @ptrCast(name_z.ptr), content_ptr) orelse return .null;
    const wrapper = try buildWrapper(ctx, doc, child);
    return .{ .object = wrapper };
}

fn sxmlAddAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const name_z = try dupZ(ctx, args[0].string);
    const val_z = try dupZ(ctx, args[1].string);
    _ = c.xmlNewProp(node, @ptrCast(name_z.ptr), @ptrCast(val_z.ptr));
    return .null;
}

fn sxmlGetNamespaces(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    var recursive: bool = false;
    if (args.len > 0 and args[0] == .bool) recursive = args[0].bool;
    const arr = try ctx.createArray();
    try collectNamespaces(ctx, node, arr, recursive);
    return .{ .array = arr };
}

fn collectNamespaces(ctx: *NativeContext, node: *c.xmlNode, arr: *PhpArray, recursive: bool) !void {
    var ns = node.nsDef;
    while (ns != null) : (ns = ns.*.next) {
        if (ns.*.href == null) continue;
        const prefix: []const u8 = if (ns.*.prefix != null) ns.*.prefix[0..cstrLen(ns.*.prefix)] else "";
        const uri = ns.*.href[0..cstrLen(ns.*.href)];
        const k = try dupString(ctx, prefix);
        const v = try dupString(ctx, uri);
        try arr.set(ctx.allocator, .{ .string = k }, .{ .string = v });
    }
    if (recursive) {
        var ch = node.children;
        while (ch != null) : (ch = ch.*.next) {
            if (ch.*.type == c.XML_ELEMENT_NODE) try collectNamespaces(ctx, ch, arr, true);
        }
    }
}

fn sxmlGetDocNamespaces(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return sxmlGetNamespaces(ctx, args);
}

fn sxmlToString(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = try dupString(ctx, "") };
    // attribute pseudo-element: return the attribute's value
    if (obj.get("__is_attr") == .bool and obj.get("__is_attr").bool) {
        const owner = getNodePtr(obj) orelse return .{ .string = try dupString(ctx, "") };
        const an = obj.get("__attr_name");
        if (an != .string) return .{ .string = try dupString(ctx, "") };
        const an_z = try dupZ(ctx, an.string);
        const v = c.xmlGetProp(owner, @ptrCast(an_z.ptr));
        if (v == null) return .{ .string = try dupString(ctx, "") };
        defer c.xmlFree.?(v);
        return .{ .string = try dupString(ctx, v[0..cstrLen(v)]) };
    }
    const node = getNodePtr(obj) orelse return .{ .string = try dupString(ctx, "") };
    // SimpleXML's __toString returns the direct text content of the element
    // (concatenation of immediate text children, not recursive)
    var out = std.ArrayList(u8){};
    defer out.deinit(ctx.allocator);
    var ch = node.children;
    while (ch != null) : (ch = ch.*.next) {
        if (ch.*.type == c.XML_TEXT_NODE or ch.*.type == c.XML_CDATA_SECTION_NODE) {
            if (ch.*.content != null) {
                const s = ch.*.content;
                try out.appendSlice(ctx.allocator, s[0..cstrLen(s)]);
            }
        }
    }
    return .{ .string = try dupString(ctx, out.items) };
}

// ---------------- magic __get / __set / iteration / offset ----------------

fn nodeInNs(n: *c.xmlNode, ns: []const u8) bool {
    if (n.ns != null and n.ns.*.href != null) {
        const href = n.ns.*.href;
        return std.mem.eql(u8, href[0..cstrLen(href)], ns);
    }
    return ns.len == 0;
}

fn sxmlIsset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const name = args[0].string;
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    const ns_v = obj.get("__ns");
    const ns_filter: ?[]const u8 = if (ns_v == .string) ns_v.string else null;
    var ch = node.children;
    while (ch != null) : (ch = ch.*.next) {
        if (ch.*.type != c.XML_ELEMENT_NODE) continue;
        if (!nameMatches(ch, name)) continue;
        if (ns_filter) |ns| if (!nodeInNs(ch, ns)) continue;
        return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn sxmlGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const name = args[0].string;
    const node = getNodePtr(obj) orelse return .null;
    const doc = getDocPtr(obj) orelse return .null;

    // honor namespace filter set by children($ns)
    const ns_v = obj.get("__ns");
    const ns_filter: ?[]const u8 = if (ns_v == .string) ns_v.string else null;

    var ch = node.children;
    while (ch != null) : (ch = ch.*.next) {
        if (ch.*.type != c.XML_ELEMENT_NODE) continue;
        if (!nameMatches(ch, name)) continue;
        if (ns_filter) |ns| if (!nodeInNs(ch, ns)) continue;
        const wrapper = try buildWrapper(ctx, doc, ch);
        // propagate namespace filter so chained child accesses keep working
        if (ns_filter) |ns| {
            const owned = try ctx.allocator.dupe(u8, ns);
            try ctx.strings.append(ctx.allocator, owned);
            try wrapper.set(ctx.allocator, "__ns", .{ .string = owned });
        }
        return .{ .object = wrapper };
    }
    return .null;
}

fn sxmlOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const doc = getDocPtr(obj) orelse return .null;

    // numeric offset: walk same-named siblings starting from $this
    if (args[0] == .int) {
        const idx = args[0].int;
        if (idx < 0) return .null;
        if (node.name == null) return .null;
        const self_name = node.name[0..cstrLen(node.name)];

        // start from the first same-named sibling under parent
        var n: ?*c.xmlNode = if (node.parent != null) node.parent.*.children else node;
        var found: i64 = 0;
        while (n != null) : (n = n.?.next) {
            const cn = n.?;
            if (cn.type == c.XML_ELEMENT_NODE and cn.name != null and std.mem.eql(u8, cn.name[0..cstrLen(cn.name)], self_name)) {
                if (found == idx) {
                    const wrapper = try buildWrapper(ctx, doc, cn);
                    return .{ .object = wrapper };
                }
                found += 1;
            }
        }
        return .null;
    }
    // string offset: attribute access
    if (args[0] == .string) {
        const attr_z = try dupZ(ctx, args[0].string);
        if (c.xmlHasProp(node, @ptrCast(attr_z.ptr)) == null) return .null;
        const wrapper = try buildAttrWrapper(ctx, doc, node, args[0].string);
        return .{ .object = wrapper };
    }
    return .null;
}

fn sxmlOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const node = getNodePtr(obj) orelse return .{ .bool = false };
    if (args[0] == .string) {
        const z = try dupZ(ctx, args[0].string);
        return .{ .bool = c.xmlHasProp(node, @ptrCast(z.ptr)) != null };
    }
    if (args[0] == .int) {
        // numeric offset: counts same-named siblings of $this
        const idx = args[0].int;
        if (idx < 0 or node.name == null) return .{ .bool = false };
        const self_name = node.name[0..cstrLen(node.name)];
        var n: ?*c.xmlNode = if (node.parent != null) node.parent.*.children else node;
        var found: i64 = 0;
        while (n != null) : (n = n.?.next) {
            const cn = n.?;
            if (cn.type == c.XML_ELEMENT_NODE and cn.name != null and std.mem.eql(u8, cn.name[0..cstrLen(cn.name)], self_name)) {
                if (found == idx) return .{ .bool = true };
                found += 1;
            }
        }
    }
    return .{ .bool = false };
}

fn sxmlOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const name_z = try dupZ(ctx, args[0].string);
    const val_z = try dupZ(ctx, args[1].string);
    _ = c.xmlSetProp(node, @ptrCast(name_z.ptr), @ptrCast(val_z.ptr));
    return .null;
}

fn sxmlOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .null;
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const name_z = try dupZ(ctx, args[0].string);
    _ = c.xmlUnsetProp(node, @ptrCast(name_z.ptr));
    return .null;
}

// iterator support: walks same-named siblings starting from this node,
// or all children if used as `foreach ($root as $k => $v)`
fn sxmlGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const node = getNodePtr(obj) orelse return .null;
    const doc = getDocPtr(obj) orelse return .null;

    // attribute view still uses the ArrayIterator path because attribute names
    // are unique per element (so dedup in a PhpArray is harmless and the
    // existing iter contract is what userland expects)
    if (obj.get("__attr_view") == .bool and obj.get("__attr_view").bool) {
        const arr = try ctx.createArray();
        var attr = node.properties;
        while (attr != null) : (attr = attr.*.next) {
            if (attr.*.name == null) continue;
            const an = attr.*.name[0..cstrLen(attr.*.name)];
            const wrapped_obj = try buildAttrWrapper(ctx, doc, node, an);
            const key = try dupString(ctx, an);
            try arr.set(ctx.allocator, .{ .string = key }, .{ .object = wrapped_obj });
        }
        const iter_obj = try ctx.createObject("ArrayIterator");
        try iter_obj.set(ctx.allocator, "__data", .{ .array = arr });
        try iter_obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        try iter_obj.set(ctx.allocator, "__flags", .{ .int = 0 });
        return .{ .object = iter_obj };
    }

    // children / sibling iteration uses a custom xml-tree walker so duplicate-
    // name children each get their own (name, child) pair in foreach
    const iter_obj = try ctx.createObject("SimpleXMLChildrenIter");
    try iter_obj.set(ctx.allocator, "__doc", .{ .int = @intCast(@intFromPtr(doc)) });
    try iter_obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    if (obj.get("__iter_children") == .bool and obj.get("__iter_children").bool) {
        // start from the node's first child
        try iter_obj.set(ctx.allocator, "__node", .{ .int = @intCast(@intFromPtr(node)) });
        try iter_obj.set(ctx.allocator, "__mode", .{ .string = "children" });
    } else {
        // sibling mode: start from $this and only emit same-named siblings
        if (node.name == null) return .{ .object = iter_obj };
        try iter_obj.set(ctx.allocator, "__node", .{ .int = @intCast(@intFromPtr(node)) });
        try iter_obj.set(ctx.allocator, "__mode", .{ .string = "siblings" });
        const name_copy = try dupString(ctx, node.name[0..cstrLen(node.name)]);
        try iter_obj.set(ctx.allocator, "__same_name", .{ .string = name_copy });
    }
    return .{ .object = iter_obj };
}

// ---------------- registration ----------------

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "SimpleXMLElement" };
    try def.interfaces.append(a, "Countable");
    try def.interfaces.append(a, "IteratorAggregate");
    try def.interfaces.append(a, "ArrayAccess");
    try def.interfaces.append(a, "Stringable");
    try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try def.methods.put(a, "asXML", .{ .name = "asXML", .arity = 0 });
    try def.methods.put(a, "saveXML", .{ .name = "saveXML", .arity = 0 });
    try def.methods.put(a, "count", .{ .name = "count", .arity = 0 });
    try def.methods.put(a, "children", .{ .name = "children", .arity = 0 });
    try def.methods.put(a, "attributes", .{ .name = "attributes", .arity = 0 });
    try def.methods.put(a, "xpath", .{ .name = "xpath", .arity = 1 });
    try def.methods.put(a, "registerXPathNamespace", .{ .name = "registerXPathNamespace", .arity = 2 });
    try def.methods.put(a, "addChild", .{ .name = "addChild", .arity = 1 });
    try def.methods.put(a, "addAttribute", .{ .name = "addAttribute", .arity = 2 });
    try def.methods.put(a, "getNamespaces", .{ .name = "getNamespaces", .arity = 0 });
    try def.methods.put(a, "getDocNamespaces", .{ .name = "getDocNamespaces", .arity = 0 });
    try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try def.methods.put(a, "__get", .{ .name = "__get", .arity = 1 });
    try def.methods.put(a, "__isset", .{ .name = "__isset", .arity = 1 });
    try def.methods.put(a, "getIterator", .{ .name = "getIterator", .arity = 0 });
    try def.methods.put(a, "offsetGet", .{ .name = "offsetGet", .arity = 1 });
    try def.methods.put(a, "offsetSet", .{ .name = "offsetSet", .arity = 2 });
    try def.methods.put(a, "offsetExists", .{ .name = "offsetExists", .arity = 1 });
    try def.methods.put(a, "offsetUnset", .{ .name = "offsetUnset", .arity = 1 });
    try vm.classes.put(a, "SimpleXMLElement", def);

    try vm.native_fns.put(a, "SimpleXMLElement::__construct", sxmlConstruct);
    try vm.native_fns.put(a, "SimpleXMLElement::getName", sxmlGetName);
    try vm.native_fns.put(a, "SimpleXMLElement::asXML", sxmlAsXML);
    try vm.native_fns.put(a, "SimpleXMLElement::saveXML", sxmlSaveXML);
    try vm.native_fns.put(a, "SimpleXMLElement::count", sxmlCount);
    try vm.native_fns.put(a, "SimpleXMLElement::children", sxmlChildren);
    try vm.native_fns.put(a, "SimpleXMLElement::attributes", sxmlAttributes);
    try vm.native_fns.put(a, "SimpleXMLElement::xpath", sxmlXpath);
    try vm.native_fns.put(a, "SimpleXMLElement::registerXPathNamespace", sxmlRegisterXPathNamespace);
    try vm.native_fns.put(a, "SimpleXMLElement::addChild", sxmlAddChild);
    try vm.native_fns.put(a, "SimpleXMLElement::addAttribute", sxmlAddAttribute);
    try vm.native_fns.put(a, "SimpleXMLElement::getNamespaces", sxmlGetNamespaces);
    try vm.native_fns.put(a, "SimpleXMLElement::getDocNamespaces", sxmlGetDocNamespaces);
    try vm.native_fns.put(a, "SimpleXMLElement::__toString", sxmlToString);
    try vm.native_fns.put(a, "SimpleXMLElement::__get", sxmlGet);
    try vm.native_fns.put(a, "SimpleXMLElement::__isset", sxmlIsset);
    try vm.native_fns.put(a, "SimpleXMLElement::getIterator", sxmlGetIterator);
    try vm.native_fns.put(a, "SimpleXMLElement::offsetGet", sxmlOffsetGet);
    try vm.native_fns.put(a, "SimpleXMLElement::offsetSet", sxmlOffsetSet);
    try vm.native_fns.put(a, "SimpleXMLElement::offsetExists", sxmlOffsetExists);
    try vm.native_fns.put(a, "SimpleXMLElement::offsetUnset", sxmlOffsetUnset);

    // SimpleXMLChildrenIter - a dedicated iterator that walks xml children/
    // siblings without going through a deduplicating PhpArray, so duplicate-
    // name siblings (multiple <a> under a parent) each get their own iteration
    // step and the foreach key is the actual element name
    var iter_def = ClassDef{ .name = "SimpleXMLChildrenIter" };
    try iter_def.interfaces.append(a, "Iterator");
    try iter_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try iter_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try iter_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try iter_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try iter_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try vm.classes.put(a, "SimpleXMLChildrenIter", iter_def);
    try vm.native_fns.put(a, "SimpleXMLChildrenIter::rewind", sxiRewind);
    try vm.native_fns.put(a, "SimpleXMLChildrenIter::valid", sxiValid);
    try vm.native_fns.put(a, "SimpleXMLChildrenIter::current", sxiCurrent);
    try vm.native_fns.put(a, "SimpleXMLChildrenIter::key", sxiKey);
    try vm.native_fns.put(a, "SimpleXMLChildrenIter::next", sxiNext);
}

// these walk xml node siblings via the underlying libxml node pointers stored
// on the SimpleXMLChildrenIter. fields: __node (starting parent or sibling),
// __doc (xmlDoc), __mode ("children" | "siblings"), __cursor (current xmlNode*
// or 0 when done), __same_name (the element name to filter by in sibling mode)

fn sxiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const node = getIterStartPtr(obj) orelse {
        try obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        return .null;
    };
    const mode = obj.get("__mode");
    const start_ptr: ?*c.xmlNode = if (mode == .string and std.mem.eql(u8, mode.string, "children"))
        @ptrCast(node.children)
    else
        node;
    var p = start_ptr;
    while (p != null) : (p = @ptrCast(p.?.next)) {
        if (sxiAcceptable(obj, p.?)) break;
    }
    const cur: usize = if (p) |np| @intFromPtr(np) else 0;
    try obj.set(ctx.allocator, "__cursor", .{ .int = @intCast(cur) });
    return .null;
}

fn sxiValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cur = obj.get("__cursor");
    return .{ .bool = cur == .int and cur.int != 0 };
}

fn sxiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cur = obj.get("__cursor");
    if (cur != .int or cur.int == 0) return .null;
    const node: *c.xmlNode = @ptrFromInt(@as(usize, @intCast(cur.int)));
    const doc: *c.xmlDoc = @ptrFromInt(@as(usize, @intCast(obj.get("__doc").int)));
    const wrapper = try buildWrapper(ctx, doc, node);
    return .{ .object = wrapper };
}

fn sxiKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cur = obj.get("__cursor");
    if (cur != .int or cur.int == 0) return .null;
    const node: *c.xmlNode = @ptrFromInt(@as(usize, @intCast(cur.int)));
    if (node.name == null) return .null;
    const name = node.name[0..cstrLen(node.name)];
    return .{ .string = try dupString(ctx, name) };
}

fn sxiNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cur = obj.get("__cursor");
    if (cur != .int or cur.int == 0) return .null;
    var p: ?*c.xmlNode = @ptrFromInt(@as(usize, @intCast(cur.int)));
    if (p) |cp| p = @ptrCast(cp.next);
    while (p != null) : (p = @ptrCast(p.?.next)) {
        if (sxiAcceptable(obj, p.?)) break;
    }
    const nxt: usize = if (p) |np| @intFromPtr(np) else 0;
    try obj.set(ctx.allocator, "__cursor", .{ .int = @intCast(nxt) });
    return .null;
}

fn sxiAcceptable(obj: *PhpObject, n: *c.xmlNode) bool {
    if (n.type != c.XML_ELEMENT_NODE) return false;
    if (n.name == null) return false;
    // sibling mode filters by element name
    const same = obj.get("__same_name");
    if (same == .string and same.string.len > 0) {
        if (!std.mem.eql(u8, n.name[0..cstrLen(n.name)], same.string)) return false;
    }
    return true;
}

fn getIterStartPtr(obj: *PhpObject) ?*c.xmlNode {
    const v = obj.get("__node");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}


pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (!std.mem.eql(u8, obj.class_name, "SimpleXMLElement")) continue;
        const owns = obj.get("__owns_doc");
        if (owns != .bool or !owns.bool) continue;
        const v = obj.get("__doc");
        if (v != .int or v.int == 0) continue;
        const doc: *c.xmlDoc = @ptrFromInt(@as(usize, @intCast(v.int)));
        c.xmlFreeDoc(doc);
    }
}
