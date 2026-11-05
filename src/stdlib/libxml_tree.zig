const std = @import("std");
const PhpObject = @import("../runtime/value.zig").PhpObject;

pub const c = @import("c_libxml_tree");

// php objects point into libxml trees. every wrapper, DOM or SimpleXML, holds
// one reference on its document and, unless it wraps the document itself, one
// on its node. the counts live in the libxml structs' _private fields, so the
// DOM and SimpleXML wrappers of one tree share them. a document is freed with
// its last reference. a node is freed with its last reference only while it is
// detached, and any descendant a wrapper still holds is unlinked first and
// lives on as a detached tree of its own

const allocator = std.heap.c_allocator;

const DocState = struct {
    refs: u32 = 0,
    // the DOMDocument wrapper, weak: it clears itself when it dies
    dom: ?*PhpObject = null,
    // the options a dead DOMDocument wrapper had, for the next one
    options: ?u16 = null,
};

const NodeState = struct {
    refs: u32 = 0,
    // the DOM wrapper, weak, so a node always comes back as the same object
    dom: ?*PhpObject = null,
};

fn docState(doc: *c.xmlDoc) ?*DocState {
    return @ptrCast(@alignCast(doc._private));
}

fn nodeState(node: *c.xmlNode) ?*NodeState {
    return @ptrCast(@alignCast(node._private));
}

pub fn isDocument(node: *const c.xmlNode) bool {
    return node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE;
}

// takes one reference on a document and one on a node in it; the document
// node itself and namespace declarations carry no node state of their own
pub fn hold(doc: ?*c.xmlDoc, node: ?*c.xmlNode) error{OutOfMemory}!void {
    const doc_state = if (doc) |d| try ensureDocState(d) else null;
    errdefer if (doc) |d| dropUnused(d);
    const node_state = if (holdable(node)) |n| try ensureNodeState(n) else null;
    if (doc_state) |state| state.refs += 1;
    if (node_state) |state| state.refs += 1;
}

pub fn release(doc: ?*c.xmlDoc, node: ?*c.xmlNode) void {
    if (holdable(node)) |n| releaseNode(n);
    if (doc) |d| releaseDoc(d);
}

fn holdable(node: ?*c.xmlNode) ?*c.xmlNode {
    const n = node orelse return null;
    if (isDocument(n) or n.type == c.XML_NAMESPACE_DECL) return null;
    return n;
}

fn ensureDocState(doc: *c.xmlDoc) error{OutOfMemory}!*DocState {
    if (docState(doc)) |state| return state;
    const fresh = try allocator.create(DocState);
    fresh.* = .{};
    doc._private = fresh;
    return fresh;
}

fn ensureNodeState(node: *c.xmlNode) error{OutOfMemory}!*NodeState {
    if (nodeState(node)) |state| return state;
    const fresh = try allocator.create(NodeState);
    fresh.* = .{};
    node._private = fresh;
    return fresh;
}

fn dropUnused(doc: *c.xmlDoc) void {
    const state = docState(doc) orelse return;
    if (state.refs > 0) return;
    doc._private = null;
    allocator.destroy(state);
}

fn releaseDoc(doc: *c.xmlDoc) void {
    const state = docState(doc) orelse return;
    state.refs -= 1;
    if (state.refs > 0) return;
    doc._private = null;
    allocator.destroy(state);
    c.xmlFreeDoc(doc);
}

fn releaseNode(node: *c.xmlNode) void {
    const state = nodeState(node) orelse return;
    state.refs -= 1;
    if (state.refs > 0) return;
    node._private = null;
    allocator.destroy(state);
    if (node.parent == null) freeTree(node);
}

pub fn isHeld(node: *c.xmlNode) bool {
    const state = nodeState(node) orelse return false;
    return state.refs > 0;
}

pub fn domWrapper(node: *c.xmlNode) ?*PhpObject {
    const state = nodeState(node) orelse return null;
    return state.dom;
}

pub fn setDomWrapper(node: *c.xmlNode, obj: ?*PhpObject) void {
    if (nodeState(node)) |state| state.dom = obj;
}

pub fn docWrapper(doc: *c.xmlDoc) ?*PhpObject {
    const state = docState(doc) orelse return null;
    return state.dom;
}

pub fn setDocWrapper(doc: *c.xmlDoc, obj: ?*PhpObject) void {
    if (docState(doc)) |state| state.dom = obj;
}

pub fn saveDocOptions(doc: *c.xmlDoc, options: u16) void {
    if (docState(doc)) |state| state.options = options;
}

pub fn savedDocOptions(doc: *c.xmlDoc) ?u16 {
    const state = docState(doc) orelse return null;
    return state.options;
}

// takes a node out of its tree for good: freed now unless a wrapper holds it
pub fn discard(node: *c.xmlNode) void {
    c.xmlUnlinkNode(node);
    if (isHeld(node)) keepNamespaces(node) else freeTree(node);
}

// before libxml frees a node's children (setting its content), the ones a
// wrapper holds are unlinked so only the unheld ones go
pub fn rescueChildren(node: *c.xmlNode) void {
    if (node.type == c.XML_ENTITY_REF_NODE) return;
    var child = node.children;
    while (child) |ch| {
        const next = ch.*.next;
        rescue(ch);
        child = next;
    }
}

fn freeTree(root: *c.xmlNode) void {
    rescueChildren(root);
    if (root.type == c.XML_ELEMENT_NODE) {
        var attr: ?*c.xmlNode = @ptrCast(root.properties);
        while (attr) |a| {
            const next: ?*c.xmlNode = @ptrCast(a.next);
            rescue(a);
            attr = next;
        }
    }
    c.xmlFreeNode(root);
}

fn rescue(node: *c.xmlNode) void {
    if (!isHeld(node)) {
        if (node.type == c.XML_DTD_NODE) return;
        rescueChildren(node);
        if (node.type == c.XML_ELEMENT_NODE) {
            var attr: ?*c.xmlNode = @ptrCast(node.properties);
            while (attr) |a| {
                const next: ?*c.xmlNode = @ptrCast(a.next);
                rescue(a);
                attr = next;
            }
        }
        return;
    }
    c.xmlUnlinkNode(node);
    keepNamespaces(node);
}

// a detached tree whose namespaces were declared on a former ancestor keeps
// them through copies on the document's oldNs list, which xmlFreeDoc frees
fn keepNamespaces(top: *c.xmlNode) void {
    fixNamespaces(top, top);
}

fn fixNamespaces(node: *c.xmlNode, top: *c.xmlNode) void {
    if (node.ns) |ns| {
        if (!declaredWithin(node, top, ns)) node.ns = storedNamespace(node.doc, top, ns);
    }
    if (node.type == c.XML_ELEMENT_NODE) {
        var attr: ?*c.xmlNode = @ptrCast(node.properties);
        while (attr) |a| : (attr = @ptrCast(a.next)) fixNamespaces(a, top);
    }
    if (node.type == c.XML_ENTITY_REF_NODE) return;
    var child = node.children;
    while (child) |ch| : (child = ch.*.next) fixNamespaces(ch, top);
}

fn declaredWithin(node: *c.xmlNode, top: *c.xmlNode, ns: *c.xmlNs) bool {
    var current: ?*c.xmlNode = node;
    while (current) |n| {
        if (n.type == c.XML_ELEMENT_NODE) {
            var decl = n.nsDef;
            while (decl) |d| : (decl = d.*.next) if (d == ns) return true;
        }
        if (n == top) return false;
        current = n.parent;
    }
    return false;
}

fn storedNamespace(doc_opt: ?*c.xmlDoc, top: *c.xmlNode, ns: *c.xmlNs) ?*c.xmlNs {
    const doc = doc_opt orelse return null;
    var existing = doc.oldNs;
    while (existing) |e| : (existing = e.*.next) {
        if (sameString(e.*.href, ns.href) and sameString(e.*.prefix, ns.prefix)) return e;
    }
    // xmlNewNs refuses the reserved xml prefix, which the document declares
    const copy = c.xmlNewNs(null, ns.href, ns.prefix) orelse return c.xmlSearchNs(doc, top, ns.prefix);
    copy.*.next = doc.oldNs;
    doc.oldNs = copy;
    return copy;
}

fn sameString(a: [*c]const u8, b: [*c]const u8) bool {
    if (a == null or b == null) return a == b;
    return std.mem.orderZ(u8, a, b) == .eq;
}
