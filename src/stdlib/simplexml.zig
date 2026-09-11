const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
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
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
    @cInclude("libxml/xpath.h");
    @cInclude("libxml/xpathInternals.h");
});

// SimpleXMLElement wraps a single xmlNodePtr plus tracking state for the
// "sibling set" semantics PHP exposes - $root->item is a wrapper around the
// first <item>, but iterating it walks all <item> siblings under $root
//
// the native handle (kind .simplexml) carries the pointers: ptr is the
// xmlNodePtr of the current element, aux the owning xmlDocPtr (owns_aux
// when this wrapper frees it at request end), extra the iteration cursor.
// a wrapper made by `clone` holds a detached node copy and marks owns so
// the request-end sweep frees it while it is still unattached
//
// state stored on the PhpObject:
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
    return obj.native.get(c.xmlNode, .simplexml);
}

fn getDocPtr(obj: *const PhpObject) ?*c.xmlDoc {
    return obj.native.getAux(c.xmlDoc, .simplexml);
}

fn getCursor(obj: *const PhpObject) ?*c.xmlNode {
    return obj.native.getExtra(c.xmlNode, .simplexml);
}

fn setCursor(obj: *PhpObject, node: ?*c.xmlNode) void {
    obj.native.extra = NativeHandle.addr(node);
}

fn setHandle(obj: *PhpObject, doc: ?*c.xmlDoc, node: ?*c.xmlNode) void {
    obj.native = .{ .kind = .simplexml, .ptr = NativeHandle.addr(node), .aux = NativeHandle.addr(doc) };
}

// php copies the whole document when the wrapper sits on the root element
// and otherwise copies just the node into the same document
fn cloneHandle(_: *VM, src: *PhpObject, copy: *PhpObject) bool {
    const node = getNodePtr(src) orelse {
        setHandle(copy, getDocPtr(src), null);
        return true;
    };
    if (isRootElement(node)) return cloneWholeDoc(node, copy);
    const dup = c.xmlDocCopyNode(node, node.doc, 1) orelse return false;
    setHandle(copy, getDocPtr(src), dup);
    copy.native.owns = true;
    return true;
}

fn isRootElement(node: *const c.xmlNode) bool {
    const parent = node.parent orelse return false;
    return parent.*.type == c.XML_DOCUMENT_NODE or parent.*.type == c.XML_HTML_DOCUMENT_NODE;
}

fn cloneWholeDoc(node: *const c.xmlNode, copy: *PhpObject) bool {
    const dup = c.xmlCopyDoc(node.doc, 1) orelse return false;
    const root = c.xmlDocGetRootElement(dup) orelse {
        c.xmlFreeDoc(dup);
        return false;
    };
    setHandle(copy, dup, root);
    copy.native.owns_aux = true;
    return true;
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
    setHandle(obj, doc, node);
    try obj.set(ctx.allocator, "__is_attr", .{ .bool = false });
    try obj.set(ctx.allocator, "__iter_children", .{ .bool = mode == .children });
    return obj;
}

fn buildAttrWrapper(ctx: *NativeContext, doc: *c.xmlDoc, owner: *c.xmlNode, attr_name: []const u8) !*PhpObject {
    const obj = try ctx.createObject("SimpleXMLElement");
    setHandle(obj, doc, owner);
    try obj.set(ctx.allocator, "__is_attr", .{ .bool = true });
    try obj.set(ctx.allocator, "__attr_name", .{ .string = Value.String.borrowed(try dupString(ctx, attr_name)) });
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
        const name_z = try dupZ(ctx, an.string.bytes());
        const v = c.xmlGetProp(node, name_z.ptr);
        if (v == null) return .{ .string = Value.String.borrowed("") };
        defer c.xmlFree.?(v);
        return .{ .string = Value.String.borrowed(try dupString(ctx, v[0..cstrLen(v)])) };
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
        if (cn.type == c.XML_ELEMENT_NODE) {
            has_elem_child = true;
            break;
        }
    }

    // PHP's json_encode on SimpleXMLElement: if the element has non-whitespace
    // text content (no element children), the text is the value. when there
    // are element children, indentation text is not considered "text content"
    // so we only flip has_text on non-whitespace runs
    var has_text = false;
    ch = @ptrCast(node.children);
    while (ch) |cn| : (ch = @ptrCast(cn.next)) {
        if (cn.type == c.XML_TEXT_NODE or cn.type == c.XML_CDATA_SECTION_NODE) {
            const txt = c.xmlNodeGetContent(cn);
            if (txt != null) {
                defer c.xmlFree.?(txt);
                const s = txt[0..cstrLen(txt)];
                if (s.len == 0) continue;
                if (has_elem_child) {
                    var any_non_ws = false;
                    for (s) |b| if (b != ' ' and b != '\t' and b != '\n' and b != '\r') {
                        any_non_ws = true;
                        break;
                    };
                    if (!any_non_ws) continue;
                }
                has_text = true;
                break;
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
        return .{ .string = Value.String.borrowed(try dupString(ctx, buf.items)) };
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
                try attrs.set(ctx.allocator, .{ .string = Value.String.borrowed(aname) }, .{ .string = Value.String.borrowed("") });
            } else {
                defer c.xmlFree.?(v);
                const vs = try dupString(ctx, v[0..cstrLen(v)]);
                try attrs.set(ctx.allocator, .{ .string = Value.String.borrowed(aname) }, .{ .string = Value.String.borrowed(vs) });
            }
        }
        try result.set(ctx.allocator, .{ .string = Value.String.borrowed("@attributes") }, .{ .array = attrs });
    }

    // walk children, grouping by element name
    ch = @ptrCast(node.children);
    while (ch) |cn| : (ch = @ptrCast(cn.next)) {
        if (cn.type != c.XML_ELEMENT_NODE) continue;
        if (cn.name == null) continue;
        const cname = try dupString(ctx, cn.name[0..cstrLen(cn.name)]);
        const child_val = try nodeToJsonValue(ctx, cn);
        const existing = result.get(.{ .string = Value.String.borrowed(cname) });
        if (existing == .null) {
            try result.set(ctx.allocator, .{ .string = Value.String.borrowed(cname) }, child_val);
        } else if (existing == .array and isSequentialList(existing.array)) {
            try existing.array.append(ctx.allocator, child_val);
        } else {
            // promote single value into a 2-element list
            const list = try ctx.allocator.create(PhpArray);
            list.* = .{};
            try ctx.vm.arrays.append(ctx.allocator, list);
            try list.append(ctx.allocator, existing);
            try list.append(ctx.allocator, child_val);
            try result.set(ctx.allocator, .{ .string = Value.String.borrowed(cname) }, .{ .array = list });
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

fn sxmlLoadString(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const src = args[0].string.bytes();
    var opts: c_int = 0;
    if (args.len > 2 and args[2] == .int) opts = @intCast(args[2].int);
    const doc = c.xmlReadMemory(src.ptr, @intCast(src.len), null, null, opts) orelse return NativeResult.scalar(.{ .bool = false });
    const root = c.xmlDocGetRootElement(doc) orelse {
        c.xmlFreeDoc(doc);
        return NativeResult.scalar(.{ .bool = false });
    };
    const wrapper = try buildRootWrapper(ctx, doc, root);
    wrapper.native.owns_aux = true;
    return NativeResult.borrowed(.{ .object = wrapper });
}

fn sxmlLoadFile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const path_z = try dupZ(ctx, args[0].string.bytes());
    var opts: c_int = 0;
    if (args.len > 2 and args[2] == .int) opts = @intCast(args[2].int);
    const doc = c.xmlReadFile(path_z.ptr, null, opts) orelse return NativeResult.scalar(.{ .bool = false });
    const root = c.xmlDocGetRootElement(doc) orelse {
        c.xmlFreeDoc(doc);
        return NativeResult.scalar(.{ .bool = false });
    };
    const wrapper = try buildRootWrapper(ctx, doc, root);
    wrapper.native.owns_aux = true;
    return NativeResult.borrowed(.{ .object = wrapper });
}

fn sxmlImportDom(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const node: *c.xmlNode = @ptrCast(dom.getNodePtr(args[0].object) orelse return NativeResult.scalar(.null));
    // for a DOMDocument, descend to root; for any node, use it
    const target: *c.xmlNode = if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE)
        c.xmlDocGetRootElement(@ptrCast(node)) orelse return NativeResult.scalar(.null)
    else
        node;
    const doc = target.doc orelse return NativeResult.scalar(.null);
    const wrapper = try buildWrapper(ctx, doc, target);
    return NativeResult.borrowed(.{ .object = wrapper });
}

// ---------------- SimpleXMLElement::__construct ----------------

fn sxmlConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const src = args[0].string.bytes();
    var opts: c_int = 0;
    if (args.len > 1 and args[1] == .int) opts = @intCast(args[1].int);
    var is_url: bool = false;
    if (args.len > 2 and args[2] == .bool) is_url = args[2].bool;

    const doc = if (is_url) blk: {
        const path_z = try dupZ(ctx, src);
        break :blk c.xmlReadFile(path_z.ptr, null, opts);
    } else c.xmlReadMemory(src.ptr, @intCast(src.len), null, null, opts);
    if (doc == null) return NativeResult.scalar(.null);

    const root = c.xmlDocGetRootElement(doc) orelse {
        c.xmlFreeDoc(doc);
        return NativeResult.scalar(.null);
    };
    setHandle(obj, doc, root);
    obj.native.owns_aux = true;
    try obj.set(ctx.allocator, "__is_attr", .{ .bool = false });
    try obj.set(ctx.allocator, "__iter_children", .{ .bool = true });
    return NativeResult.scalar(.null);
}

// ---------------- methods ----------------

fn sxmlGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (obj.get("__is_attr") == .bool and obj.get("__is_attr").bool) {
        const an = obj.get("__attr_name");
        if (an == .string) return NativeResult.share(an);
    }
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    if (node.name == null) return NativeResult.scalar(.null);
    return try NativeResult.copyString(ctx.allocator, node.name[0..cstrLen(node.name)]);
}

fn sxmlAsXML(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

    if (args.len > 0 and args[0] == .string) {
        const path_z = try dupZ(ctx, args[0].string.bytes());
        const written = c.xmlSaveFormatFile(path_z.ptr, doc, 0);
        return NativeResult.scalar(.{ .bool = written >= 0 });
    }

    // is this the root element? PHP returns full doc XML; otherwise just node fragment
    const root = c.xmlDocGetRootElement(doc);
    if (root != null and root == node) {
        var out: [*c]u8 = null;
        var size: c_int = 0;
        c.xmlDocDumpFormatMemoryEnc(doc, &out, &size, doc.*.encoding, 0);
        if (out == null) return NativeResult.scalar(.{ .bool = false });
        defer c.xmlFree.?(out);
        return try NativeResult.copyString(ctx.allocator, out[0..@intCast(size)]);
    }

    const buf = c.xmlBufferCreate();
    defer c.xmlBufferFree(buf);
    _ = c.xmlNodeDump(buf, doc, node, 0, 0);
    const content = c.xmlBufferContent(buf);
    if (content == null) return try NativeResult.copyString(ctx.allocator, "");
    return try NativeResult.copyString(ctx.allocator, content[0..cstrLen(content)]);
}

fn sxmlSaveXML(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sxmlAsXML(ctx, args);
}

fn sxmlCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    // count matches iteration: children-mode counts child elements; sibling-mode
    // counts same-named siblings of $this; attr-view counts attributes
    if (obj.get("__attr_view") == .bool and obj.get("__attr_view").bool) {
        var count: i64 = 0;
        var attr = node.properties;
        while (attr != null) : (attr = attr.*.next) count += 1;
        return NativeResult.scalar(.{ .int = count });
    }
    if (obj.get("__iter_children") == .bool and obj.get("__iter_children").bool) {
        const ns_v = obj.get("__ns");
        const ns_filter: ?[]const u8 = if (ns_v == .string) ns_v.string.bytes() else null;
        var count: i64 = 0;
        var child = node.children;
        while (child != null) : (child = child.*.next) {
            if (child.*.type != c.XML_ELEMENT_NODE) continue;
            if (ns_filter) |ns| if (!nodeInNs(child, ns)) continue;
            count += 1;
        }
        return NativeResult.scalar(.{ .int = count });
    }
    if (node.name == null) return NativeResult.scalar(.{ .int = 0 });
    const self_name = node.name[0..cstrLen(node.name)];
    var count: i64 = 0;
    var ch: ?*c.xmlNode = node;
    while (ch != null) : (ch = ch.?.next) {
        const cn = ch.?;
        if (cn.type != c.XML_ELEMENT_NODE) continue;
        if (cn.name == null) continue;
        if (std.mem.eql(u8, cn.name[0..cstrLen(cn.name)], self_name)) count += 1;
    }
    return NativeResult.scalar(.{ .int = count });
}

fn sxmlChildren(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);
    // ->children() must yield the node's CHILDREN, not iterate same-named
    // siblings of the node itself - that's the default sibling-mode wrapper
    const wrapper = try buildWrapperMode(ctx, doc, node, .children);
    // PHP: children(string $ns = null, bool $isPrefix = false). The default
    // (no arg or empty string with isPrefix=false) yields children in the
    // null/empty namespace, not all children. Set __ns to mark which ns to
    // filter on; iteration / count / __get all honor it
    var resolved_ns: []const u8 = "";
    if (args.len >= 1 and args[0] == .string) {
        const ns_or_prefix = args[0].string.bytes();
        const is_prefix = args.len >= 2 and args[1] == .bool and args[1].bool;
        resolved_ns = ns_or_prefix;
        if (is_prefix) {
            const prefix_z = try dupZ(ctx, ns_or_prefix);
            const ns = c.xmlSearchNs(doc, node, @ptrCast(prefix_z.ptr));
            if (ns != null and ns.*.href != null) {
                const href = ns.*.href;
                resolved_ns = href[0..cstrLen(href)];
            }
        }
    }
    const owned = try ctx.allocator.dupe(u8, resolved_ns);
    try ctx.strings.append(ctx.allocator, owned);
    try wrapper.set(ctx.allocator, "__ns", .{ .string = Value.String.borrowed(owned) });
    return NativeResult.borrowed(.{ .object = wrapper });
}

fn sxmlAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);
    const wrapper = try ctx.createObject("SimpleXMLElement");
    setHandle(wrapper, doc, node);
    try wrapper.set(ctx.allocator, "__is_attr", .{ .bool = false });
    try wrapper.set(ctx.allocator, "__attr_view", .{ .bool = true });
    // namespace filter mirrors children(): when called without args, PHP only
    // emits no-namespace attrs (so empty string __ns acts as the default)
    var resolved_ns: []const u8 = "";
    if (args.len >= 1 and args[0] == .string) {
        const ns_or_prefix = args[0].string.bytes();
        const is_prefix = args.len >= 2 and args[1] == .bool and args[1].bool;
        resolved_ns = ns_or_prefix;
        if (is_prefix) {
            const prefix_z = try dupZ(ctx, ns_or_prefix);
            const ns = c.xmlSearchNs(doc, node, @ptrCast(prefix_z.ptr));
            if (ns != null and ns.*.href != null) {
                const href = ns.*.href;
                resolved_ns = href[0..cstrLen(href)];
            }
        }
    }
    const owned = try ctx.allocator.dupe(u8, resolved_ns);
    try ctx.strings.append(ctx.allocator, owned);
    try wrapper.set(ctx.allocator, "__ns", .{ .string = Value.String.borrowed(owned) });
    return NativeResult.borrowed(.{ .object = wrapper });
}

// walks all element nodes from the given root, registering each declared
// xmlns:prefix mapping into the xpath context. mirrors PHP's behavior where
// `SimpleXMLElement::xpath('//ns:item')` works without an explicit register
fn autoRegisterNamespaces(ctx: *NativeContext, xctx: *c.xmlXPathContext, node: *c.xmlNode) !void {
    var ns = node.nsDef;
    while (ns != null) : (ns = ns.*.next) {
        if (ns.*.href == null) continue;
        const prefix = if (ns.*.prefix != null) ns.*.prefix[0..cstrLen(ns.*.prefix)] else continue;
        const prefix_z = try dupZ(ctx, prefix);
        const uri_z = try dupZ(ctx, ns.*.href[0..cstrLen(ns.*.href)]);
        _ = c.xmlXPathRegisterNs(xctx, @ptrCast(prefix_z.ptr), @ptrCast(uri_z.ptr));
    }
    var ch = node.children;
    while (ch != null) : (ch = ch.*.next) {
        if (ch.*.type == c.XML_ELEMENT_NODE) try autoRegisterNamespaces(ctx, xctx, ch);
    }
}

fn sxmlXpath(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

    const xctx = c.xmlXPathNewContext(doc) orelse return NativeResult.scalar(.{ .bool = false });
    defer c.xmlXPathFreeContext(xctx);
    xctx.*.node = node;

    // auto-register namespaces declared in the document (matches PHP's
    // SimpleXMLElement::xpath which walks xmlDoc's namespace table)
    {
        const root = c.xmlDocGetRootElement(doc);
        if (root != null) try autoRegisterNamespaces(ctx, xctx, root);
    }
    // also register any namespaces stored on this wrapper via registerXPathNamespace
    const ns_map = obj.get("__namespaces");
    if (ns_map == .array) {
        for (ns_map.array.entries.items) |e| {
            if (e.key != .string or e.value != .string) continue;
            const prefix_z = try dupZ(ctx, e.key.string.bytes());
            const uri_z = try dupZ(ctx, e.value.string.bytes());
            _ = c.xmlXPathRegisterNs(xctx, @ptrCast(prefix_z.ptr), @ptrCast(uri_z.ptr));
        }
    }

    const expr_z = try dupZ(ctx, args[0].string.bytes());
    const result = c.xmlXPathEvalExpression(@ptrCast(expr_z.ptr), xctx);
    if (result == null) return NativeResult.scalar(.{ .bool = false });
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
    return NativeResult.borrowed(.{ .array = arr });
}

fn sxmlRegisterXPathNamespace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    var ns_map = obj.get("__namespaces");
    if (ns_map != .array) {
        const arr = try ctx.createArray();
        try obj.set(ctx.allocator, "__namespaces", .{ .array = arr });
        ns_map = .{ .array = arr };
    }
    const key = try dupString(ctx, args[0].string.bytes());
    const val = try dupString(ctx, args[1].string.bytes());
    try ns_map.array.set(ctx.allocator, .{ .string = Value.String.borrowed(key) }, .{ .string = Value.String.borrowed(val) });
    return NativeResult.scalar(.{ .bool = true });
}

fn sxmlAddChild(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);
    const content_z: ?[:0]u8 = if (args.len > 1 and args[1] == .string) try dupZ(ctx, args[1].string.bytes()) else null;
    const ns_str: ?[]const u8 = if (args.len > 2 and args[2] == .string and args[2].string.bytes().len > 0) args[2].string.bytes() else null;

    // split "prefix:local" so the namespace is created with the right prefix
    // (PHP attaches xmlns:prefix to the new child rather than xmlns on root)
    const raw_name = args[0].string.bytes();
    var prefix_part: ?[]const u8 = null;
    var local_name = raw_name;
    if (std.mem.indexOfScalar(u8, raw_name, ':')) |colon| {
        prefix_part = raw_name[0..colon];
        local_name = raw_name[colon + 1 ..];
    }
    const local_z = try dupZ(ctx, local_name);

    var ns_ptr: ?*c.xmlNs = null;
    if (ns_str) |ns_href| {
        const href_z = try dupZ(ctx, ns_href);
        ns_ptr = c.xmlSearchNsByHref(doc, node, @ptrCast(href_z.ptr));
        if (ns_ptr == null) {
            if (prefix_part) |p| {
                const prefix_z = try dupZ(ctx, p);
                ns_ptr = c.xmlNewNs(null, @ptrCast(href_z.ptr), @ptrCast(prefix_z.ptr));
            } else {
                ns_ptr = c.xmlNewNs(null, @ptrCast(href_z.ptr), null);
            }
        }
    }
    const content_ptr: [*c]const u8 = if (content_z) |cz| @ptrCast(cz.ptr) else null;
    const child_raw = c.xmlNewTextChild(node, ns_ptr, @ptrCast(local_z.ptr), content_ptr);
    if (child_raw == null) return NativeResult.scalar(.null);
    const child: *c.xmlNode = @ptrCast(child_raw);
    // attach the namespace to the child itself so it serializes as
    // <prefix:local xmlns:prefix="..."> when the prefix wasn't already in scope
    if (ns_ptr) |np| if (np.*.context == null) {
        np.*.next = child.nsDef;
        child.nsDef = np;
    };
    const wrapper = try buildWrapper(ctx, doc, child);
    return NativeResult.borrowed(.{ .object = wrapper });
}

fn sxmlAddAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const val_z = try dupZ(ctx, args[1].string.bytes());
    _ = c.xmlNewProp(node, @ptrCast(name_z.ptr), @ptrCast(val_z.ptr));
    return NativeResult.scalar(.null);
}

fn sxmlGetNamespaces(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    var recursive: bool = false;
    if (args.len > 0 and args[0] == .bool) recursive = args[0].bool;
    const arr = try ctx.createArray();
    try collectNamespaces(ctx, node, arr, recursive);
    return NativeResult.borrowed(.{ .array = arr });
}

fn collectNamespaces(ctx: *NativeContext, node: *c.xmlNode, arr: *PhpArray, recursive: bool) !void {
    var ns = node.nsDef;
    while (ns != null) : (ns = ns.*.next) {
        if (ns.*.href == null) continue;
        const prefix: []const u8 = if (ns.*.prefix != null) ns.*.prefix[0..cstrLen(ns.*.prefix)] else "";
        const uri = ns.*.href[0..cstrLen(ns.*.href)];
        const k = try dupString(ctx, prefix);
        const v = try dupString(ctx, uri);
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(k) }, .{ .string = Value.String.borrowed(v) });
    }
    if (recursive) {
        var ch = node.children;
        while (ch != null) : (ch = ch.*.next) {
            if (ch.*.type == c.XML_ELEMENT_NODE) try collectNamespaces(ctx, ch, arr, true);
        }
    }
}

fn sxmlGetDocNamespaces(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return sxmlGetNamespaces(ctx, args);
}

fn sxmlToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return try NativeResult.copyString(ctx.allocator, "");
    // attribute pseudo-element: return the attribute's value
    if (obj.get("__is_attr") == .bool and obj.get("__is_attr").bool) {
        const owner = getNodePtr(obj) orelse return try NativeResult.copyString(ctx.allocator, "");
        const an = obj.get("__attr_name");
        if (an != .string) return try NativeResult.copyString(ctx.allocator, "");
        const an_z = try dupZ(ctx, an.string.bytes());
        const ns_v = obj.get("__attr_ns");
        const v: [*c]u8 = if (ns_v == .string and ns_v.string.bytes().len > 0) blk: {
            const ns_z = try dupZ(ctx, ns_v.string.bytes());
            break :blk c.xmlGetNsProp(owner, @ptrCast(an_z.ptr), @ptrCast(ns_z.ptr));
        } else c.xmlGetProp(owner, @ptrCast(an_z.ptr));
        if (v == null) return try NativeResult.copyString(ctx.allocator, "");
        defer c.xmlFree.?(v);
        return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
    }
    const node = getNodePtr(obj) orelse return try NativeResult.copyString(ctx.allocator, "");
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
    return try NativeResult.copyString(ctx.allocator, out.items);
}

// ---------------- magic __get / __set / iteration / offset ----------------

fn nodeInNs(n: *c.xmlNode, ns: []const u8) bool {
    if (n.ns != null and n.ns.*.href != null) {
        const href = n.ns.*.href;
        return std.mem.eql(u8, href[0..cstrLen(href)], ns);
    }
    return ns.len == 0;
}

fn sxmlIsset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const ns_v = obj.get("__ns");
    const ns_filter: ?[]const u8 = if (ns_v == .string) ns_v.string.bytes() else null;
    var ch = node.children;
    while (ch != null) : (ch = ch.*.next) {
        if (ch.*.type != c.XML_ELEMENT_NODE) continue;
        if (!nameMatches(ch, name)) continue;
        if (ns_filter) |ns| if (!nodeInNs(ch, ns)) continue;
        return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn sxmlGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = args[0].string.bytes();
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);

    // honor namespace filter set by children($ns) / attributes($ns)
    const ns_v = obj.get("__ns");
    const ns_filter: ?[]const u8 = if (ns_v == .string) ns_v.string.bytes() else null;

    // when the wrapper is an attribute view, $wrap->name returns an attribute
    // wrapper instead of looking for a child element
    if (obj.get("__attr_view") == .bool and obj.get("__attr_view").bool) {
        const wrap = try buildAttrWrapper(ctx, doc, node, name);
        if (ns_filter) |ns| {
            const owned = try dupString(ctx, ns);
            try wrap.set(ctx.allocator, "__attr_ns", .{ .string = Value.String.borrowed(owned) });
        }
        return NativeResult.borrowed(.{ .object = wrap });
    }

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
            try wrapper.set(ctx.allocator, "__ns", .{ .string = Value.String.borrowed(owned) });
        }
        return NativeResult.borrowed(.{ .object = wrapper });
    }
    return NativeResult.scalar(.null);
}

fn sxmlOffsetGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);

    // numeric offset: walk same-named siblings starting from $this
    if (args[0] == .int) {
        const idx = args[0].int;
        if (idx < 0) return NativeResult.scalar(.null);
        if (node.name == null) return NativeResult.scalar(.null);
        const self_name = node.name[0..cstrLen(node.name)];

        // start from the first same-named sibling under parent
        var n: ?*c.xmlNode = if (node.parent != null) node.parent.*.children else node;
        var found: i64 = 0;
        while (n != null) : (n = n.?.next) {
            const cn = n.?;
            if (cn.type == c.XML_ELEMENT_NODE and cn.name != null and std.mem.eql(u8, cn.name[0..cstrLen(cn.name)], self_name)) {
                if (found == idx) {
                    const wrapper = try buildWrapper(ctx, doc, cn);
                    return NativeResult.borrowed(.{ .object = wrapper });
                }
                found += 1;
            }
        }
        return NativeResult.scalar(.null);
    }
    // string offset: attribute access
    if (args[0] == .string) {
        const attr_z = try dupZ(ctx, args[0].string.bytes());
        if (c.xmlHasProp(node, @ptrCast(attr_z.ptr)) == null) return NativeResult.scalar(.null);
        const wrapper = try buildAttrWrapper(ctx, doc, node, args[0].string.bytes());
        return NativeResult.borrowed(.{ .object = wrapper });
    }
    return NativeResult.scalar(.null);
}

fn sxmlOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (args[0] == .string) {
        const z = try dupZ(ctx, args[0].string.bytes());
        return NativeResult.scalar(.{ .bool = c.xmlHasProp(node, @ptrCast(z.ptr)) != null });
    }
    if (args[0] == .int) {
        // numeric offset: counts same-named siblings of $this
        const idx = args[0].int;
        if (idx < 0 or node.name == null) return NativeResult.scalar(.{ .bool = false });
        const self_name = node.name[0..cstrLen(node.name)];
        var n: ?*c.xmlNode = if (node.parent != null) node.parent.*.children else node;
        var found: i64 = 0;
        while (n != null) : (n = n.?.next) {
            const cn = n.?;
            if (cn.type == c.XML_ELEMENT_NODE and cn.name != null and std.mem.eql(u8, cn.name[0..cstrLen(cn.name)], self_name)) {
                if (found == idx) return NativeResult.scalar(.{ .bool = true });
                found += 1;
            }
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn sxmlOffsetSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    // numeric offset: replace text content of the Nth same-named sibling
    if (args[0] == .int) {
        const idx = args[0].int;
        if (idx < 0 or node.name == null) return NativeResult.scalar(.null);
        const self_name = node.name[0..cstrLen(node.name)];
        var n: ?*c.xmlNode = if (node.parent != null) node.parent.*.children else node;
        var found: i64 = 0;
        while (n != null) : (n = n.?.next) {
            const cn = n.?;
            if (cn.type == c.XML_ELEMENT_NODE and cn.name != null and std.mem.eql(u8, cn.name[0..cstrLen(cn.name)], self_name)) {
                if (found == idx) {
                    if (args[1] == .string) try setNodeText(ctx, cn, args[1].string.bytes());
                    return NativeResult.scalar(.null);
                }
                found += 1;
            }
        }
        return NativeResult.scalar(.null);
    }
    if (args[0] != .string or args[1] != .string) return NativeResult.scalar(.null);
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const val_z = try dupZ(ctx, args[1].string.bytes());
    _ = c.xmlSetProp(node, @ptrCast(name_z.ptr), @ptrCast(val_z.ptr));
    return NativeResult.scalar(.null);
}

// replaces the text content of an element node with the supplied string.
// removes all existing text/element children first so the post-state is a
// single text node, matching PHP's `$elem->child = 'value'` semantics
fn setNodeText(ctx: *NativeContext, n: *c.xmlNode, text: []const u8) !void {
    var ch = n.children;
    while (ch != null) {
        const nxt = ch.*.next;
        c.xmlUnlinkNode(ch);
        c.xmlFreeNode(ch);
        ch = nxt;
    }
    const tz = try dupZ(ctx, text);
    const txt_node = c.xmlNewText(@ptrCast(tz.ptr));
    if (txt_node != null) _ = c.xmlAddChild(n, txt_node);
}

fn sxmlSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const new_text: []const u8 = switch (args[1]) {
        .string => |s| s.bytes(),
        .int => |i| blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch break :blk "";
            break :blk try dupString(ctx, s);
        },
        .float => |f| blk: {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch break :blk "";
            break :blk try dupString(ctx, s);
        },
        .bool => |b| if (b) "1" else "",
        else => return NativeResult.scalar(.null),
    };
    // find existing child with this element name; if not found, create one
    var ch = node.children;
    while (ch != null) : (ch = ch.*.next) {
        if (ch.*.type == c.XML_ELEMENT_NODE and nameMatches(ch, args[0].string.bytes())) {
            try setNodeText(ctx, ch, new_text);
            return NativeResult.scalar(.null);
        }
    }
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const val_z = try dupZ(ctx, new_text);
    _ = c.xmlNewTextChild(node, null, @ptrCast(name_z.ptr), @ptrCast(val_z.ptr));
    return NativeResult.scalar(.null);
}

fn sxmlOffsetUnset(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const name_z = try dupZ(ctx, args[0].string.bytes());
    _ = c.xmlUnsetProp(node, @ptrCast(name_z.ptr));
    return NativeResult.scalar(.null);
}

// iterator support: walks same-named siblings starting from this node,
// or all children if used as `foreach ($root as $k => $v)`
fn sxmlGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);

    // attribute view still uses the ArrayIterator path because attribute names
    // are unique per element (so dedup in a PhpArray is harmless and the
    // existing iter contract is what userland expects)
    if (obj.get("__attr_view") == .bool and obj.get("__attr_view").bool) {
        const ns_v = obj.get("__ns");
        const ns_filter: ?[]const u8 = if (ns_v == .string) ns_v.string.bytes() else null;
        const arr = try ctx.createArray();
        var attr = node.properties;
        while (attr != null) : (attr = attr.*.next) {
            if (attr.*.name == null) continue;
            if (ns_filter) |ns| {
                const has_ns = attr.*.ns != null and attr.*.ns.*.href != null;
                if (ns.len == 0 and has_ns) continue;
                if (ns.len > 0) {
                    if (!has_ns) continue;
                    const href = attr.*.ns.*.href;
                    if (!std.mem.eql(u8, href[0..cstrLen(href)], ns)) continue;
                }
            }
            const an = attr.*.name[0..cstrLen(attr.*.name)];
            const wrapped_obj = try buildAttrWrapper(ctx, doc, node, an);
            // remember which namespace the attr was sourced from so __toString
            // can resolve via xmlGetNsProp instead of xmlGetProp
            if (attr.*.ns != null and attr.*.ns.*.href != null) {
                const href = attr.*.ns.*.href;
                const owned = try dupString(ctx, href[0..cstrLen(href)]);
                try wrapped_obj.set(ctx.allocator, "__attr_ns", .{ .string = Value.String.borrowed(owned) });
            }
            const key = try dupString(ctx, an);
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(key) }, .{ .object = wrapped_obj });
        }
        const iter_obj = try ctx.createObject("ArrayIterator");
        try iter_obj.set(ctx.allocator, "__data", .{ .array = arr });
        try iter_obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
        try iter_obj.set(ctx.allocator, "__flags", .{ .int = 0 });
        return NativeResult.borrowed(.{ .object = iter_obj });
    }

    // children / sibling iteration uses a custom xml-tree walker so duplicate-
    // name children each get their own (name, child) pair in foreach
    const iter_obj = try ctx.createObject("SimpleXMLChildrenIter");
    setHandle(iter_obj, doc, null);
    // forward namespace filter from the wrapper to the iter so sxiAcceptable
    // can drop nodes outside the requested namespace
    const fwd_ns = obj.get("__ns");
    if (fwd_ns == .string) try iter_obj.set(ctx.allocator, "__ns", .{ .string = fwd_ns.string });
    if (obj.get("__iter_children") == .bool and obj.get("__iter_children").bool) {
        // start from the node's first child
        iter_obj.native.ptr = @intFromPtr(node);
        try iter_obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("children") });
    } else {
        // sibling mode: start from $this and only emit same-named siblings
        if (node.name == null) return NativeResult.borrowed(.{ .object = iter_obj });
        iter_obj.native.ptr = @intFromPtr(node);
        try iter_obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("siblings") });
        const name_copy = try dupString(ctx, node.name[0..cstrLen(node.name)]);
        try iter_obj.set(ctx.allocator, "__same_name", .{ .string = Value.String.borrowed(name_copy) });
    }
    return NativeResult.borrowed(.{ .object = iter_obj });
}

// ---------------- registration ----------------

pub fn register(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "SimpleXMLElement", .native_clone = cloneHandle };
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
    try def.methods.put(a, "__set", .{ .name = "__set", .arity = 2 });
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
    try vm.native_fns.put(a, "SimpleXMLElement::__set", sxmlSet);
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

    // SimpleXMLIterator extends SimpleXMLElement and adds hasChildren /
    // getChildren on top of the regular iteration methods. it's used with
    // RecursiveIteratorIterator so just expose the class with parent = SXE
    var sxi_def = ClassDef{ .name = "SimpleXMLIterator", .parent = "SimpleXMLElement", .native_clone = cloneHandle };
    try sxi_def.interfaces.append(a, "RecursiveIterator");
    try sxi_def.methods.put(a, "hasChildren", .{ .name = "hasChildren", .arity = 0 });
    try sxi_def.methods.put(a, "getChildren", .{ .name = "getChildren", .arity = 0 });
    try sxi_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try sxi_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try sxi_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try sxi_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try sxi_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try vm.classes.put(a, "SimpleXMLIterator", sxi_def);
    try vm.native_fns.put(a, "SimpleXMLIterator::hasChildren", sxmlIterHasChildren);
    try vm.native_fns.put(a, "SimpleXMLIterator::getChildren", sxmlIterGetChildren);
    // share the same node-walker the SimpleXMLChildrenIter helper uses; the
    // SimpleXMLIterator's $this object keeps its own cursor in its handle
    try vm.native_fns.put(a, "SimpleXMLIterator::rewind", sxmlIterRewind);
    try vm.native_fns.put(a, "SimpleXMLIterator::valid", sxiValid);
    try vm.native_fns.put(a, "SimpleXMLIterator::current", sxmlIterCurrent);
    try vm.native_fns.put(a, "SimpleXMLIterator::key", sxiKey);
    try vm.native_fns.put(a, "SimpleXMLIterator::next", sxiNext);
}

fn sxmlIterRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // SimpleXMLIterator iterates the children of $this. seed __mode and start
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__mode", .{ .string = Value.String.borrowed("children") });
    try obj.set(ctx.allocator, "__same_name", .{ .string = Value.String.borrowed("") });
    return sxiRewind(ctx, &.{});
}

fn sxmlIterCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // wrap the child node as another SimpleXMLIterator so the foreach value
    // also implements RecursiveIterator (needed by RecursiveIteratorIterator)
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getCursor(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);
    const wrapper = try ctx.createObject("SimpleXMLIterator");
    setHandle(wrapper, doc, node);
    try wrapper.set(ctx.allocator, "__is_attr", .{ .bool = false });
    try wrapper.set(ctx.allocator, "__iter_children", .{ .bool = true });
    return NativeResult.borrowed(.{ .object = wrapper });
}

// hasChildren / getChildren operate on the CURRENT iteration position (cursor)
// not the wrapper's own node. zphp's RecursiveIteratorIterator calls these
// on the iterator itself between valid() and current(), expecting them to
// describe the element about to be yielded
fn sxmlIterHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getCursor(obj) orelse return NativeResult.scalar(.{ .bool = false });
    var ch = node.children;
    while (ch != null) : (ch = ch.*.next) {
        if (ch.*.type == c.XML_ELEMENT_NODE) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn sxmlIterGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getCursor(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);
    const wrapper = try ctx.createObject("SimpleXMLIterator");
    setHandle(wrapper, doc, node);
    try wrapper.set(ctx.allocator, "__is_attr", .{ .bool = false });
    try wrapper.set(ctx.allocator, "__iter_children", .{ .bool = true });
    return NativeResult.borrowed(.{ .object = wrapper });
}

// these walk xml node siblings via the libxml node pointers in the
// SimpleXMLChildrenIter's handle: ptr is the starting parent or sibling, aux
// the xmlDoc, extra the cursor (null when done). properties: __mode
// ("children" | "siblings"), __same_name (the element name to filter by in
// sibling mode)

fn sxiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse {
        setCursor(obj, null);
        return NativeResult.scalar(.null);
    };
    const mode = obj.get("__mode");
    const start_ptr: ?*c.xmlNode = if (mode == .string and std.mem.eql(u8, mode.string.bytes(), "children"))
        @ptrCast(node.children)
    else
        node;
    var p = start_ptr;
    while (p != null) : (p = @ptrCast(p.?.next)) {
        if (sxiAcceptable(obj, p.?)) break;
    }
    setCursor(obj, p);
    return NativeResult.scalar(.null);
}

fn sxiValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = getCursor(obj) != null });
}

fn sxiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getCursor(obj) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);
    const wrapper = try buildWrapper(ctx, doc, node);
    return NativeResult.borrowed(.{ .object = wrapper });
}

fn sxiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getCursor(obj) orelse return NativeResult.scalar(.null);
    if (node.name == null) return NativeResult.scalar(.null);
    const name = node.name[0..cstrLen(node.name)];
    return try NativeResult.copyString(ctx.allocator, name);
}

fn sxiNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cur = getCursor(obj) orelse return NativeResult.scalar(.null);
    var p: ?*c.xmlNode = @ptrCast(cur.next);
    while (p != null) : (p = @ptrCast(p.?.next)) {
        if (sxiAcceptable(obj, p.?)) break;
    }
    setCursor(obj, p);
    return NativeResult.scalar(.null);
}

fn sxiAcceptable(obj: *PhpObject, n: *c.xmlNode) bool {
    if (n.type != c.XML_ELEMENT_NODE) return false;
    if (n.name == null) return false;
    // sibling mode filters by element name
    const same = obj.get("__same_name");
    if (same == .string and same.string.bytes().len > 0) {
        if (!std.mem.eql(u8, n.name[0..cstrLen(n.name)], same.string.bytes())) return false;
    }
    // namespace filter set by children() / attributes() with a $ns arg
    const ns_v = obj.get("__ns");
    if (ns_v == .string) {
        const has_ns = n.ns != null and n.ns.*.href != null;
        if (ns_v.string.bytes().len == 0) {
            if (has_ns) return false;
        } else {
            if (!has_ns) return false;
            const href = n.ns.*.href;
            if (!std.mem.eql(u8, href[0..cstrLen(href)], ns_v.string.bytes())) return false;
        }
    }
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| freeDetachedCopy(obj);
    for (objects.items) |obj| {
        if (!std.mem.eql(u8, obj.class_name, "SimpleXMLElement")) continue;
        if (!obj.native.owns_aux) continue;
        if (getDocPtr(obj)) |doc| c.xmlFreeDoc(doc);
    }
}

// a cloned node that was appended somewhere is freed with its tree
fn freeDetachedCopy(obj: *PhpObject) void {
    if (!obj.native.owns) return;
    const node = getNodePtr(obj) orelse return;
    if (node.parent == null) c.xmlFreeNode(node);
}
