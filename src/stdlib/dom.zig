const std = @import("std");
const sync = @import("../sync.zig");
const paths = @import("../paths.zig");
const bundle = @import("../bundle.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeHandle = @import("../runtime/value.zig").NativeHandle;
const vm_mod = @import("../runtime/vm.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const NativeFn = *const fn (*NativeContext, []const Value) RuntimeError!NativeResult;

pub const tree = @import("libxml_tree.zig");
pub const c = tree.c;

var global_init = sync.once(globalInit);

fn ensureGlobalInit() void {
    global_init.call();
}

fn globalInit() void {
    c.xmlInitParser();
    // suppress libxml2's default stderr output for parse errors;
    // PHP also defaults to silent unless libxml_use_internal_errors(true)
    c.xmlSetGenericErrorFunc(null, silentErrorHandler);
    // structured handler captures detailed error info per call when
    // libxml_internal_errors_enabled is on; otherwise it's a noop
    c.xmlSetStructuredErrorFunc(null, structuredErrorHandler);
}

fn silentErrorHandler(_: ?*anyopaque, _: [*c]const u8, ...) callconv(.c) void {}

const CapturedError = struct {
    level: i32,
    code: i32,
    line: i32,
    column: i32,
    message: []u8,
    file: ?[]u8,
};

var captured_errors: std.ArrayListUnmanaged(CapturedError) = .empty;
// allocator for the captured-error buffers - shared global since libxml's
// callback fires from C with no zphp context. uses page_allocator which is
// always-available and doesn't depend on the per-script arena being live
var capture_allocator: std.mem.Allocator = std.heap.page_allocator;

fn structuredErrorHandler(_: ?*anyopaque, err_ptr: [*c]const c.xmlError) callconv(.c) void {
    if (!libxml_internal_errors_enabled) return;
    if (err_ptr == null) return;
    const err = err_ptr.*;
    var msg_len: usize = 0;
    if (err.message != null) {
        while (err.message[msg_len] != 0) msg_len += 1;
        // strip trailing newline that libxml always appends
        if (msg_len > 0 and err.message[msg_len - 1] == '\n') msg_len -= 1;
    }
    const msg_buf = capture_allocator.alloc(u8, msg_len) catch return;
    if (msg_len > 0) @memcpy(msg_buf, err.message[0..msg_len]);
    var file_buf: ?[]u8 = null;
    if (err.file != null) {
        var fl: usize = 0;
        while (err.file[fl] != 0) fl += 1;
        if (fl > 0) {
            const b = capture_allocator.alloc(u8, fl) catch {
                captured_errors.append(capture_allocator, .{
                    .level = @intCast(err.level),
                    .code = @intCast(err.code),
                    .line = @intCast(err.line),
                    .column = 0,
                    .message = msg_buf,
                    .file = null,
                }) catch return;
                return;
            };
            @memcpy(b, err.file[0..fl]);
            file_buf = b;
        }
    }
    captured_errors.append(capture_allocator, .{
        .level = @intCast(err.level),
        .code = @intCast(err.code),
        .line = @intCast(err.line),
        .column = 0,
        .message = msg_buf,
        .file = file_buf,
    }) catch return;
}

fn freeCapturedError(e: *const CapturedError) void {
    capture_allocator.free(e.message);
    if (e.file) |f| capture_allocator.free(f);
}

// ---------------- pointer storage on PhpObject ----------------
// a wrapper's native handle (kind .dom) has the node it wraps in ptr (the
// xmlDoc itself for a DOMDocument) and in aux the document it holds a
// reference on. libxml_tree.zig counts those references: a document lives
// while any wrapper points into it, a detached node while its wrappers live,
// and each node has one DOM wrapper at a time so it comes back as the same
// object

pub fn getNodePtr(obj: *const PhpObject) ?*c.xmlNode {
    return obj.native.get(c.xmlNode, .dom);
}

fn getDocPtr(obj: *const PhpObject) ?*c.xmlDoc {
    return obj.native.getAux(c.xmlDoc, .dom);
}

fn attachNode(obj: *PhpObject, node: *c.xmlNode) !void {
    try tree.hold(node.doc, node);
    obj.native = .{ .kind = .dom, .ptr = @intFromPtr(node), .aux = NativeHandle.addr(node.doc) };
    tree.setDomWrapper(node, obj);
}

fn attachDocument(obj: *PhpObject, doc: *c.xmlDoc) !void {
    try tree.hold(doc, null);
    obj.native = .{ .kind = .dom, .ptr = @intFromPtr(doc), .aux = @intFromPtr(doc) };
    tree.setDocWrapper(doc, obj);
}

// drops what a wrapper holds; the tree goes when nothing else holds it
fn detach(obj: *PhpObject) void {
    if (obj.native.kind != .dom) return;
    const node = getNodePtr(obj);
    const doc = getDocPtr(obj);
    obj.native = .{};
    if (node) |n| {
        if (tree.isDocument(n)) {
            const d: *c.xmlDoc = @ptrCast(n);
            if (tree.docWrapper(d) == obj) {
                tree.setDocWrapper(d, null);
                tree.saveDocOptions(d, documentOptions(obj));
            }
        } else if (tree.domWrapper(n) == obj) tree.setDomWrapper(n, null);
    }
    tree.release(doc, node);
}

fn cleanupWrapper(obj: *PhpObject) bool {
    detach(obj);
    return true;
}

// the DOMDocument options php keeps with the document, not the wrapper
const document_options = [_][]const u8{ "formatOutput", "preserveWhiteSpace", "validateOnParse", "resolveExternals", "substituteEntities", "strictErrorChecking", "recover" };
const default_document_options: u16 = 0b0100010;

fn documentOptions(obj: *const PhpObject) u16 {
    var bits: u16 = 0;
    for (document_options, 0..) |name, i| {
        const v = obj.get(name);
        if (v == .bool and v.bool) bits |= @as(u16, 1) << @intCast(i);
    }
    return bits;
}

fn setDocumentOptions(ctx: *NativeContext, obj: *PhpObject, bits: u16) !void {
    for (document_options, 0..) |name, i| {
        try obj.set(ctx.allocator, name, .{ .bool = bits & (@as(u16, 1) << @intCast(i)) != 0 });
    }
}

// ---------------- clone ----------------

fn cloneDocHandle(_: *VM, src: *PhpObject, copy: *PhpObject) bool {
    const doc = getDocPtr(src) orelse return true;
    const dup = c.xmlCopyDoc(doc, 1) orelse return false;
    attachDocument(copy, dup) catch {
        c.xmlFreeDoc(dup);
        return false;
    };
    return true;
}

fn cloneNodeHandle(_: *VM, src: *PhpObject, copy: *PhpObject) bool {
    const node = getNodePtr(src) orelse return true;
    const dup = c.xmlDocCopyNode(node, node.doc, 1) orelse return false;
    attachNode(copy, dup) catch {
        c.xmlFreeNode(dup);
        return false;
    };
    return true;
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

// a copy that lives until the next statement boundary unless stored
fn dupString(ctx: *NativeContext, s: []const u8) !Value.String {
    return ctx.vm.transientBytes(s);
}

fn dupZ(ctx: *NativeContext, s: []const u8) ![:0]const u8 {
    return ctx.vm.transientZ(s);
}

// a file path as php's stream layer opens it, null-terminated for libxml
fn filePathZ(ctx: *NativeContext, path: []const u8) ![:0]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    return dupZ(ctx, paths.streamPath(&buf, path));
}

fn cstrLen(p: [*c]const u8) usize {
    return std.mem.len(p);
}

fn cstrToValue(ctx: *NativeContext, p: [*c]const u8) RuntimeError!NativeResult {
    if (p == null) return NativeResult.scalar(.null);
    const slice = p[0..cstrLen(p)];
    return try NativeResult.copyString(ctx.allocator, slice);
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

// the wrapper of a node: the one it already has, or a new one
pub fn wrapNode(ctx: *NativeContext, node: ?*c.xmlNode) !Value {
    const n = node orelse return .null;
    if (tree.isDocument(n)) return wrapDocument(ctx, @ptrCast(n));
    if (tree.domWrapper(n)) |existing| return .{ .object = existing };
    const obj = try ctx.createObject(classForNodeType(n.type));
    try attachNode(obj, n);
    return .{ .object = obj };
}

fn wrapDocument(ctx: *NativeContext, doc: *c.xmlDoc) !Value {
    if (tree.docWrapper(doc)) |existing| return .{ .object = existing };
    const obj = try ctx.createObject("DOMDocument");
    try setDocumentOptions(ctx, obj, tree.savedDocOptions(doc) orelse default_document_options);
    try attachDocument(obj, doc);
    return .{ .object = obj };
}

// ---------------- DOMDocument methods ----------------

fn domDocConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    ensureGlobalInit();
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);

    var version: []const u8 = "1.0";
    var encoding: []const u8 = "";
    if (args.len > 0 and args[0] == .string) version = args[0].string.bytes();
    if (args.len > 1 and args[1] == .string) encoding = args[1].string.bytes();

    const version_z = try dupZ(ctx, version);
    const doc = c.xmlNewDoc(@ptrCast(version_z.ptr)) orelse return NativeResult.scalar(.null);
    if (encoding.len > 0) {
        const enc_z = try dupZ(ctx, encoding);
        doc.*.encoding = c.xmlStrdup(@ptrCast(enc_z.ptr));
    }
    try setDocumentOptions(ctx, obj, default_document_options);
    try replaceDocument(obj, doc);
    return NativeResult.scalar(.null);
}

// a load swaps the wrapper onto the new document; nodes of the old one keep it
// alive and get a fresh DOMDocument for ownerDocument
fn replaceDocument(obj: *PhpObject, doc: *c.xmlDoc) !void {
    detach(obj);
    attachDocument(obj, doc) catch |err| {
        c.xmlFreeDoc(doc);
        return err;
    };
}

fn loaded(obj: *PhpObject, doc: ?*c.xmlDoc) RuntimeError!NativeResult {
    try replaceDocument(obj, doc orelse return NativeResult.scalar(.{ .bool = false }));
    return NativeResult.scalar(.{ .bool = true });
}

fn parseOptions(args: []const Value, idx: usize) c_int {
    if (args.len > idx and args[idx] == .int) return @intCast(args[idx].int);
    return 0;
}

fn domDocLoadXML(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const src = args[0].string.bytes();
    const opts = parseOptions(args, 1);

    return loaded(obj, c.xmlReadMemory(src.ptr, @intCast(src.len), null, null, opts));
}

fn domDocSchemaValidateSource(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const source = args[0].string.bytes();
    const parser_ctx = c.xmlSchemaNewMemParserCtxt(source.ptr, @intCast(source.len)) orelse return NativeResult.scalar(.{ .bool = false });
    defer c.xmlSchemaFreeParserCtxt(parser_ctx);
    const schema = c.xmlSchemaParse(parser_ctx) orelse return NativeResult.scalar(.{ .bool = false });
    defer c.xmlSchemaFree(schema);
    const valid_ctx = c.xmlSchemaNewValidCtxt(schema) orelse return NativeResult.scalar(.{ .bool = false });
    defer c.xmlSchemaFreeValidCtxt(valid_ctx);
    return NativeResult.scalar(.{ .bool = c.xmlSchemaValidateDoc(valid_ctx, doc) == 0 });
}

fn domDocLoad(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const path_z = try filePathZ(ctx, args[0].string.bytes());
    const opts = parseOptions(args, 1);

    return loaded(obj, if (bundle.packedSource(path_z)) |src| c.xmlReadMemory(src.ptr, @intCast(src.len), path_z.ptr, null, opts) else c.xmlReadFile(path_z.ptr, null, opts));
}

fn domDocLoadHTML(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const src = args[0].string.bytes();
    const opts = parseOptions(args, 1);

    return loaded(obj, c.htmlReadMemory(src.ptr, @intCast(src.len), null, null, opts));
}

fn domDocLoadHTMLFile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const path_z = try filePathZ(ctx, args[0].string.bytes());
    const opts = parseOptions(args, 1);

    return loaded(obj, if (bundle.packedSource(path_z)) |src| c.htmlReadMemory(src.ptr, @intCast(src.len), path_z.ptr, null, opts) else c.htmlReadFile(path_z.ptr, null, opts));
}

fn formatOutputOn(obj: *PhpObject) bool {
    const v = obj.get("formatOutput");
    return v == .bool and v.bool;
}

fn domDocSaveXML(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

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
        if (out == null) return try NativeResult.copyString(ctx.allocator, "");
        const slice = out[0..cstrLen(out)];
        return try NativeResult.copyString(ctx.allocator, slice);
    }

    // full doc. pass NULL encoding when the document doesn't have one so libxml2
    // matches PHP's saveXML output (no `encoding="..."` attribute in the prolog)
    var out: [*c]u8 = null;
    var size: c_int = 0;
    const fmt: c_int = if (formatOutputOn(obj)) 1 else 0;
    c.xmlDocDumpFormatMemoryEnc(doc, &out, &size, doc.*.encoding, fmt);
    if (out == null) return NativeResult.scalar(.{ .bool = false });
    defer c.xmlFree.?(out);
    const slice = out[0..@intCast(size)];
    return try NativeResult.copyString(ctx.allocator, slice);
}

fn domDocSaveHTML(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

    if (args.len > 0 and args[0] == .object) {
        const n = getNodePtr(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
        const buf = c.xmlBufferCreate();
        defer c.xmlBufferFree(buf);
        _ = c.htmlNodeDump(buf, doc, n);
        const out = c.xmlBufferContent(buf);
        if (out == null) return try NativeResult.copyString(ctx.allocator, "");
        const slice = out[0..cstrLen(out)];
        return try NativeResult.copyString(ctx.allocator, slice);
    }

    var out: [*c]u8 = null;
    var size: c_int = 0;
    c.htmlDocDumpMemory(doc, &out, &size);
    if (out == null) return NativeResult.scalar(.{ .bool = false });
    defer c.xmlFree.?(out);
    const slice = out[0..@intCast(size)];
    return try NativeResult.copyString(ctx.allocator, slice);
}

fn domDocSave(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const path_z = try filePathZ(ctx, args[0].string.bytes());
    const fmt: c_int = if (formatOutputOn(obj)) 1 else 0;
    bundle.prepareWrite(path_z, .create);
    const written = c.xmlSaveFormatFile(path_z.ptr, doc, fmt);
    if (written < 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(written) });
}

fn domDocCreateElement(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const node = c.xmlNewDocNode(doc, null, @ptrCast(name_z.ptr), null) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len > 1 and args[1] == .string and args[1].string.bytes().len > 0) {
        const text_z = try dupZ(ctx, args[1].string.bytes());
        const tn = c.xmlNewDocText(doc, @ptrCast(text_z.ptr));
        _ = c.xmlAddChild(node, tn);
    }
    return NativeResult.borrowed(try wrapNode(ctx, node));
}

fn domDocCreateTextNode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const text_z = try dupZ(ctx, args[0].string.bytes());
    const node = c.xmlNewDocText(doc, @ptrCast(text_z.ptr)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(try wrapNode(ctx, node));
}

fn domDocCreateComment(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const text_z = try dupZ(ctx, args[0].string.bytes());
    const node = c.xmlNewDocComment(doc, @ptrCast(text_z.ptr)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(try wrapNode(ctx, node));
}

fn domDocCreateCDATASection(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const text = args[0].string.bytes();
    const node = c.xmlNewCDataBlock(doc, @ptrCast(text.ptr), @intCast(text.len)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(try wrapNode(ctx, node));
}

fn domDocCreateAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const name_z = try dupZ(ctx, args[0].string.bytes());
    // detached attribute: create via xmlNewDocProp on null parent
    const attr = c.xmlNewDocProp(doc, @ptrCast(name_z.ptr), null) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(try wrapNode(ctx, @ptrCast(attr)));
}

fn domDocCreateElementNS(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

    const ns_uri: ?[]const u8 = if (args[0] == .string) args[0].string.bytes() else null;
    const qname = args[1].string.bytes();

    // split qname into prefix:localname
    var prefix_buf: ?[:0]const u8 = null;
    var local_buf: [:0]const u8 = undefined;
    if (std.mem.indexOfScalar(u8, qname, ':')) |colon| {
        prefix_buf = try dupZ(ctx, qname[0..colon]);
        local_buf = try dupZ(ctx, qname[colon + 1 ..]);
    } else {
        local_buf = try dupZ(ctx, qname);
    }

    const node = c.xmlNewDocNode(doc, null, @ptrCast(local_buf.ptr), null) orelse return NativeResult.scalar(.{ .bool = false });
    if (ns_uri) |uri| {
        const uri_z = try dupZ(ctx, uri);
        const prefix_ptr: [*c]const u8 = if (prefix_buf) |p| @ptrCast(p.ptr) else null;
        const ns = c.xmlNewNs(node, @ptrCast(uri_z.ptr), prefix_ptr);
        c.xmlSetNs(node, ns);
    }
    if (args.len > 2 and args[2] == .string and args[2].string.bytes().len > 0) {
        const text_z = try dupZ(ctx, args[2].string.bytes());
        const tn = c.xmlNewDocText(doc, @ptrCast(text_z.ptr));
        _ = c.xmlAddChild(node, tn);
    }
    return NativeResult.borrowed(try wrapNode(ctx, node));
}

fn domDocCreateDocumentFragment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const node = c.xmlNewDocFragment(doc) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(try wrapNode(ctx, node));
}

fn domDocImportNode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const src = getNodePtr(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    const deep: c_int = if (args.len > 1 and args[1] == .bool and args[1].bool) 1 else 0;
    const copy = c.xmlDocCopyNode(src, doc, if (deep != 0) 1 else 2);
    if (copy == null) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(try wrapNode(ctx, copy));
}

fn domDocGetElementsByTagName(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();

    const root = c.xmlDocGetRootElement(doc);
    var list = std.ArrayList(*c.xmlNode).empty;
    defer list.deinit(ctx.allocator);
    if (root) |r| {
        try collectByName(ctx.allocator, r, name, &list);
    }
    return try makeNodeList(ctx, list.items);
}

fn domDocGetElementById(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const doc = getDocPtr(obj) orelse return NativeResult.scalar(.null);
    const id_z = try dupZ(ctx, args[0].string.bytes());
    const attr = c.xmlGetID(doc, @ptrCast(id_z.ptr));
    if (attr == null) {
        // fall back to scanning for any attribute named "id" with this value
        const root = c.xmlDocGetRootElement(doc);
        if (root) |r| {
            if (findById(r, args[0].string.bytes())) |n| return NativeResult.borrowed(try wrapNode(ctx, n));
        }
        return NativeResult.scalar(.null);
    }
    return NativeResult.borrowed(try wrapNode(ctx, @ptrCast(attr.*.parent)));
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

fn domDocNormalizeDocument(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    _ = ctx;
    // PHP's normalizeDocument coalesces adjacent text nodes; libxml2 does this on saveXML.
    // no-op here is observably equivalent for the common path
    return NativeResult.scalar(.null);
}

// ---------------- DOMNode read-only accessors ----------------

// magic getter dispatched via __get for read-only properties on DOM* objects.
// register native __get on each DOM* class and route by property name
fn domGenericGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const prop = args[0].string.bytes();
    return try readProperty(ctx, obj, prop);
}

fn domGenericSet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const prop = args[0].string.bytes();
    const val = args[1];

    if (std.mem.eql(u8, prop, "nodeValue") or std.mem.eql(u8, prop, "textContent")) {
        const s = if (val == .string) val.string.bytes() else "";
        try setContent(ctx, node, s);
        return NativeResult.scalar(.null);
    }
    if (std.mem.eql(u8, prop, "data") and (node.type == c.XML_TEXT_NODE or node.type == c.XML_CDATA_SECTION_NODE or node.type == c.XML_COMMENT_NODE)) {
        try setContent(ctx, node, if (val == .string) val.string.bytes() else "");
        return NativeResult.scalar(.null);
    }
    if (std.mem.eql(u8, prop, "value") and node.type == c.XML_ATTRIBUTE_NODE) {
        try setContent(ctx, node, if (val == .string) val.string.bytes() else "");
        return NativeResult.scalar(.null);
    }
    // unrecognized property: fall back to stashing in PhpObject (matches the
    // legacy dynamic-property behavior so tests aren't surprised)
    try obj.set(ctx.allocator, prop, val);
    return NativeResult.scalar(.null);
}

// libxml frees the children it replaces; the ones a wrapper holds are taken
// out first and live on detached
fn setContent(ctx: *NativeContext, node: *c.xmlNode, text: []const u8) !void {
    const text_z = try dupZ(ctx, text);
    tree.rescueChildren(node);
    _ = c.xmlNodeSetContent(node, @ptrCast(text_z.ptr));
}

fn readProperty(ctx: *NativeContext, obj: *PhpObject, prop: []const u8) RuntimeError!NativeResult {
    // namespace pseudo-nodes are stored as standalone PhpObjects with their
    // prefix+href captured as properties (not via __node, since the underlying
    // xmlNs is freed when the XPath result is). short-circuit before any
    // __node-based dereference
    if (obj.get("__ns_kind") == .bool and obj.get("__ns_kind").bool) {
        if (std.mem.eql(u8, prop, "nodeName")) {
            const px = obj.get("__ns_prefix");
            if (px == .string and px.string.bytes().len > 0) {
                const out = try std.fmt.allocPrint(ctx.allocator, "xmlns:{s}", .{px.string.bytes()});
                return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
            }
            return try NativeResult.copyString(ctx.allocator, "xmlns");
        }
        if (std.mem.eql(u8, prop, "nodeValue") or std.mem.eql(u8, prop, "value")) {
            const href = obj.get("__ns_href");
            if (href == .string) return NativeResult.share(href);
            return try NativeResult.copyString(ctx.allocator, "");
        }
        if (std.mem.eql(u8, prop, "nodeType")) return NativeResult.scalar(.{ .int = @intCast(c.XML_NAMESPACE_DECL) });
        return NativeResult.scalar(.null);
    }

    const node_opt = getNodePtr(obj);
    if (node_opt == null) return NativeResult.scalar(.null);
    const node = node_opt.?;

    if (std.mem.eql(u8, prop, "nodeName")) {
        // for documents, return "#document"
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE) {
            return try NativeResult.copyString(ctx.allocator, "#document");
        }
        if (node.type == c.XML_TEXT_NODE) return try NativeResult.copyString(ctx.allocator, "#text");
        if (node.type == c.XML_CDATA_SECTION_NODE) return try NativeResult.copyString(ctx.allocator, "#cdata-section");
        if (node.type == c.XML_COMMENT_NODE) return try NativeResult.copyString(ctx.allocator, "#comment");
        if (node.type == c.XML_DOCUMENT_FRAG_NODE) return try NativeResult.copyString(ctx.allocator, "#document-fragment");
        // for elements, include prefix if namespaced
        if (node.type == c.XML_ELEMENT_NODE and node.ns != null and node.ns.*.prefix != null) {
            const prefix = node.ns.*.prefix;
            const name = node.name;
            const out = try std.fmt.allocPrint(ctx.allocator, "{s}:{s}", .{
                prefix[0..cstrLen(prefix)],
                name[0..cstrLen(name)],
            });
            return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
        }
        return try cstrToValue(ctx, node.name);
    }
    if (std.mem.eql(u8, prop, "nodeValue")) {
        // PHP returns concatenated text content for elements; null for documents
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE or node.type == c.XML_DOCUMENT_TYPE_NODE) {
            return NativeResult.scalar(.null);
        }
        const content = c.xmlNodeGetContent(node);
        if (content == null) return try NativeResult.copyString(ctx.allocator, "");
        defer c.xmlFree.?(content);
        const slice = content[0..cstrLen(content)];
        return try NativeResult.copyString(ctx.allocator, slice);
    }
    if (std.mem.eql(u8, prop, "textContent")) {
        const content = c.xmlNodeGetContent(node);
        if (content == null) return try NativeResult.copyString(ctx.allocator, "");
        defer c.xmlFree.?(content);
        const slice = content[0..cstrLen(content)];
        return try NativeResult.copyString(ctx.allocator, slice);
    }
    if (std.mem.eql(u8, prop, "nodeType")) {
        return NativeResult.scalar(.{ .int = @intCast(node.type) });
    }
    if (std.mem.eql(u8, prop, "parentNode")) {
        return NativeResult.borrowed(try wrapNode(ctx, node.parent));
    }
    if (std.mem.eql(u8, prop, "firstChild")) {
        return NativeResult.borrowed(try wrapNode(ctx, node.children));
    }
    if (std.mem.eql(u8, prop, "lastChild")) {
        return NativeResult.borrowed(try wrapNode(ctx, node.last));
    }
    if (std.mem.eql(u8, prop, "previousSibling")) {
        return NativeResult.borrowed(try wrapNode(ctx, node.prev));
    }
    if (std.mem.eql(u8, prop, "nextSibling")) {
        return NativeResult.borrowed(try wrapNode(ctx, node.next));
    }
    if (std.mem.eql(u8, prop, "previousElementSibling")) {
        var p = node.prev;
        while (p != null and p.*.type != c.XML_ELEMENT_NODE) : (p = p.*.prev) {}
        return NativeResult.borrowed(try wrapNode(ctx, p));
    }
    if (std.mem.eql(u8, prop, "nextElementSibling")) {
        var n = node.next;
        while (n != null and n.*.type != c.XML_ELEMENT_NODE) : (n = n.*.next) {}
        return NativeResult.borrowed(try wrapNode(ctx, n));
    }
    if (std.mem.eql(u8, prop, "firstElementChild")) {
        var k = node.children;
        while (k != null and k.*.type != c.XML_ELEMENT_NODE) : (k = k.*.next) {}
        return NativeResult.borrowed(try wrapNode(ctx, k));
    }
    if (std.mem.eql(u8, prop, "lastElementChild")) {
        var k = node.last;
        while (k != null and k.*.type != c.XML_ELEMENT_NODE) : (k = k.*.prev) {}
        return NativeResult.borrowed(try wrapNode(ctx, k));
    }
    if (std.mem.eql(u8, prop, "childElementCount")) {
        var k = node.children;
        var count: i64 = 0;
        while (k != null) : (k = k.*.next) {
            if (k.*.type == c.XML_ELEMENT_NODE) count += 1;
        }
        return NativeResult.scalar(.{ .int = count });
    }
    if (std.mem.eql(u8, prop, "childNodes")) {
        var list = std.ArrayList(*c.xmlNode).empty;
        defer list.deinit(ctx.allocator);
        var child = node.children;
        while (child != null) : (child = child.*.next) try list.append(ctx.allocator, child);
        return try makeNodeList(ctx, list.items);
    }
    if (std.mem.eql(u8, prop, "ownerDocument")) {
        if (tree.isDocument(node)) return NativeResult.scalar(.null);
        const doc = node.doc orelse return NativeResult.scalar(.null);
        return NativeResult.borrowed(try wrapDocument(ctx, doc));
    }
    if (std.mem.eql(u8, prop, "documentElement")) {
        if (node.type != c.XML_DOCUMENT_NODE and node.type != c.XML_HTML_DOCUMENT_NODE) return NativeResult.scalar(.null);
        const doc: *c.xmlDoc = @ptrCast(node);
        return NativeResult.borrowed(try wrapNode(ctx, c.xmlDocGetRootElement(doc)));
    }
    if (std.mem.eql(u8, prop, "namespaceURI")) {
        if (node.ns != null and node.ns.*.href != null) return try cstrToValue(ctx, node.ns.*.href);
        return NativeResult.scalar(.null);
    }
    if (std.mem.eql(u8, prop, "prefix")) {
        if (node.ns != null and node.ns.*.prefix != null) return try cstrToValue(ctx, node.ns.*.prefix);
        return try NativeResult.copyString(ctx.allocator, "");
    }
    if (std.mem.eql(u8, prop, "localName")) {
        if (node.type == c.XML_ELEMENT_NODE or node.type == c.XML_ATTRIBUTE_NODE) {
            return try cstrToValue(ctx, node.name);
        }
        return NativeResult.scalar(.null);
    }
    if (std.mem.eql(u8, prop, "baseURI")) {
        const u = c.xmlNodeGetBase(@ptrCast(node.doc), node);
        if (u == null) return NativeResult.scalar(.null);
        defer c.xmlFree.?(u);
        return try NativeResult.copyString(ctx.allocator, u[0..cstrLen(u)]);
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
                return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
            }
            return try cstrToValue(ctx, node.name);
        }
    }
    if (std.mem.eql(u8, prop, "attributes")) {
        if (node.type != c.XML_ELEMENT_NODE) return NativeResult.scalar(.null);
        return try makeNamedNodeMap(ctx, node);
    }
    if (std.mem.eql(u8, prop, "data") or std.mem.eql(u8, prop, "value")) {
        const content = c.xmlNodeGetContent(node);
        if (content == null) return try NativeResult.copyString(ctx.allocator, "");
        defer c.xmlFree.?(content);
        return try NativeResult.copyString(ctx.allocator, content[0..cstrLen(content)]);
    }
    if (std.mem.eql(u8, prop, "length")) {
        const content = c.xmlNodeGetContent(node);
        if (content == null) return NativeResult.scalar(.{ .int = 0 });
        defer c.xmlFree.?(content);
        return NativeResult.scalar(.{ .int = @intCast(cstrLen(content)) });
    }
    if (std.mem.eql(u8, prop, "name")) {
        if (node.type == c.XML_ATTRIBUTE_NODE) return try cstrToValue(ctx, node.name);
    }
    if (std.mem.eql(u8, prop, "ownerElement")) {
        if (node.type == c.XML_ATTRIBUTE_NODE) return NativeResult.borrowed(try wrapNode(ctx, node.parent));
    }
    if (std.mem.eql(u8, prop, "encoding")) {
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE) {
            const doc: *c.xmlDoc = @ptrCast(node);
            if (doc.*.encoding != null) return try cstrToValue(ctx, doc.*.encoding);
            return NativeResult.scalar(.null);
        }
    }
    if (std.mem.eql(u8, prop, "version") or std.mem.eql(u8, prop, "xmlVersion")) {
        if (node.type == c.XML_DOCUMENT_NODE or node.type == c.XML_HTML_DOCUMENT_NODE) {
            const doc: *c.xmlDoc = @ptrCast(node);
            if (doc.*.version != null) return try cstrToValue(ctx, doc.*.version);
            return NativeResult.scalar(.null);
        }
    }
    return NativeResult.scalar(.null);
}

// ---------------- DOMNode write methods ----------------

// php's legacy DOM refuses children under nodes that cannot have them by
// returning false, and throws for the rest of the structural errors
fn childrenAllowed(node: *const c.xmlNode) bool {
    return switch (node.type) {
        c.XML_DOCUMENT_TYPE_NODE, c.XML_DTD_NODE, c.XML_PI_NODE, c.XML_COMMENT_NODE, c.XML_TEXT_NODE, c.XML_CDATA_SECTION_NODE, c.XML_NOTATION_NODE => false,
        else => true,
    };
}

const DomError = enum(i64) {
    hierarchy_request = 3,
    wrong_document = 4,
    not_found = 8,

    fn message(self: DomError) []const u8 {
        return switch (self) {
            .hierarchy_request => "Hierarchy Request Error",
            .wrong_document => "Wrong Document Error",
            .not_found => "Not Found Error",
        };
    }
};

fn throwDom(ctx: *NativeContext, err: DomError) RuntimeError!NativeResult {
    try ctx.vm.setPendingException("DOMException", err.message());
    try ctx.vm.pending_exception.?.object.set(ctx.allocator, "code", .{ .int = @intFromEnum(err) });
    return error.RuntimeError;
}

fn isAncestorOrSelf(candidate: *const c.xmlNode, node: *const c.xmlNode) bool {
    var current: ?*const c.xmlNode = node;
    while (current) |n| : (current = n.parent) if (n == candidate) return true;
    return false;
}

fn insertionError(parent: *const c.xmlNode, child: *const c.xmlNode) ?DomError {
    if (tree.isDocument(child) or isAncestorOrSelf(child, parent)) return .hierarchy_request;
    const parent_doc: ?*const c.xmlDoc = if (tree.isDocument(parent)) @ptrCast(parent) else parent.doc;
    if (child.doc != null and child.doc != parent_doc) return .wrong_document;
    return null;
}

// puts child under parent before `before` (at the end when null). a fragment
// hands over its children; an attribute replaces the one of the same name
fn insertChild(parent: *c.xmlNode, child: *c.xmlNode, before: ?*c.xmlNode) void {
    if (child.type == c.XML_DOCUMENT_FRAG_NODE) {
        var moving = child.children;
        while (moving) |m| {
            const next = m.*.next;
            c.xmlUnlinkNode(m);
            link(parent, m, before);
            moving = next;
        }
        return;
    }
    c.xmlUnlinkNode(child);
    if (child.type == c.XML_ATTRIBUTE_NODE) {
        if (parent.type != c.XML_ELEMENT_NODE) return;
        const href: [*c]const u8 = if (child.ns != null) child.ns.*.href else null;
        if (c.xmlHasNsProp(parent, child.name, href)) |existing| {
            const existing_node: *c.xmlNode = @ptrCast(existing);
            if (existing_node != child and existing_node.type == c.XML_ATTRIBUTE_NODE) tree.discard(existing_node);
        }
        _ = c.xmlAddChild(parent, child);
        return;
    }
    link(parent, child, before);
}

// links by hand: xmlAddChild merges a text node into a text neighbour and
// frees it, which php never does
fn link(parent: *c.xmlNode, child: *c.xmlNode, before: ?*c.xmlNode) void {
    const prev: ?*c.xmlNode = if (before) |b| b.prev else parent.last;
    child.parent = parent;
    child.prev = prev;
    child.next = before;
    if (prev) |p| p.next = child else parent.children = child;
    if (before) |b| b.prev = child else parent.last = child;
}

fn insertAt(ctx: *NativeContext, parent: *c.xmlNode, child_obj: *PhpObject, before: ?*c.xmlNode) RuntimeError!NativeResult {
    const child = getNodePtr(child_obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (!childrenAllowed(parent)) return NativeResult.scalar(.{ .bool = false });
    if (insertionError(parent, child)) |err| return throwDom(ctx, err);
    if (child == before) return NativeResult.borrowed(.{ .object = child_obj });
    insertChild(parent, child, before);
    return NativeResult.borrowed(.{ .object = child_obj });
}

fn domNodeAppendChild(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const parent = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return insertAt(ctx, parent, args[0].object, null);
}

fn domNodeInsertBefore(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const parent = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    var before: ?*c.xmlNode = null;
    if (args.len > 1 and args[1] == .object) {
        before = getNodePtr(args[1].object) orelse return NativeResult.scalar(.{ .bool = false });
        if (before.?.parent != parent) return throwDom(ctx, .not_found);
    }
    return insertAt(ctx, parent, args[0].object, before);
}

fn domNodeRemoveChild(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const parent = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const child = getNodePtr(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    if (!childrenAllowed(parent)) return NativeResult.scalar(.{ .bool = false });
    if (child.parent != parent) return throwDom(ctx, .not_found);
    c.xmlUnlinkNode(child);
    return NativeResult.borrowed(.{ .object = args[0].object });
}

fn domNodeReplaceChild(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object or args[1] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const parent = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const new_node = getNodePtr(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    const old_node = getNodePtr(args[1].object) orelse return NativeResult.scalar(.{ .bool = false });
    if (!childrenAllowed(parent)) return NativeResult.scalar(.{ .bool = false });
    if (old_node.parent != parent) return throwDom(ctx, .not_found);
    if (insertionError(parent, new_node)) |err| return throwDom(ctx, err);
    if (new_node != old_node) {
        insertChild(parent, new_node, old_node);
        c.xmlUnlinkNode(old_node);
    }
    return NativeResult.borrowed(.{ .object = args[1].object });
}

fn domNodeCloneNode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const deep: c_int = if (args.len > 0 and args[0] == .bool and args[0].bool) 1 else 2;
    const copy = c.xmlDocCopyNode(node, node.doc, deep);
    return NativeResult.borrowed(try wrapNode(ctx, copy));
}

fn domNodeHasChildNodes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = node.children != null });
}

fn domNodeHasAttributes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (node.type != c.XML_ELEMENT_NODE) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = node.properties != null });
}

fn domNodeIsSameNode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const a = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const b = getNodePtr(args[0].object) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = a == b });
}

fn domNodeGetNodePath(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const p = c.xmlGetNodePath(node);
    if (p == null) return NativeResult.scalar(.null);
    defer c.xmlFree.?(p);
    return try NativeResult.copyString(ctx.allocator, p[0..cstrLen(p)]);
}

fn domNodeGetLineNo(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(c.xmlGetLineNo(node)) });
}

fn domNodeLookupPrefix(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const uri_z = try dupZ(ctx, args[0].string.bytes());
    const ns = c.xmlSearchNsByHref(node.doc, node, @ptrCast(uri_z.ptr));
    if (ns == null or ns.*.prefix == null) return NativeResult.scalar(.null);
    return try cstrToValue(ctx, ns.*.prefix);
}

fn domNodeLookupNamespaceURI(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const prefix_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.bytes().len > 0)
        @ptrCast((try dupZ(ctx, args[0].string.bytes())).ptr)
    else
        null;
    const ns = c.xmlSearchNs(node.doc, node, prefix_ptr);
    if (ns == null or ns.*.href == null) return NativeResult.scalar(.null);
    return try cstrToValue(ctx, ns.*.href);
}

// ---------------- DOMElement methods ----------------

fn domElementGetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return try NativeResult.copyString(ctx.allocator, "");
    const obj = getThis(ctx) orelse return try NativeResult.copyString(ctx.allocator, "");
    const node = getNodePtr(obj) orelse return try NativeResult.copyString(ctx.allocator, "");
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const v = c.xmlGetProp(node, @ptrCast(name_z.ptr));
    if (v == null) return try NativeResult.copyString(ctx.allocator, "");
    defer c.xmlFree.?(v);
    return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
}

fn domElementSetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const val_z = try dupZ(ctx, args[1].string.bytes());
    if (c.xmlHasProp(node, @ptrCast(name_z.ptr))) |existing| tree.rescueChildren(@ptrCast(existing));
    const attr = c.xmlSetProp(node, @ptrCast(name_z.ptr), @ptrCast(val_z.ptr));
    if (attr == null) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(try wrapNode(ctx, @ptrCast(attr)));
}

fn domElementHasAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const name_z = try dupZ(ctx, args[0].string.bytes());
    return NativeResult.scalar(.{ .bool = c.xmlHasProp(node, @ptrCast(name_z.ptr)) != null });
}

fn domElementRemoveAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const name_z = try dupZ(ctx, args[0].string.bytes());
    return NativeResult.scalar(.{ .bool = discardAttribute(c.xmlHasProp(node, @ptrCast(name_z.ptr))) });
}

fn discardAttribute(found: ?*c.xmlAttr) bool {
    const attr: *c.xmlNode = @ptrCast(found orelse return false);
    if (attr.type != c.XML_ATTRIBUTE_NODE) return false;
    tree.discard(attr);
    return true;
}

fn domElementGetAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return try NativeResult.copyString(ctx.allocator, "");
    const obj = getThis(ctx) orelse return try NativeResult.copyString(ctx.allocator, "");
    const node = getNodePtr(obj) orelse return try NativeResult.copyString(ctx.allocator, "");
    const ns_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.bytes().len > 0)
        @ptrCast((try dupZ(ctx, args[0].string.bytes())).ptr)
    else
        null;
    const name_z = try dupZ(ctx, args[1].string.bytes());
    const v = c.xmlGetNsProp(node, @ptrCast(name_z.ptr), ns_ptr);
    if (v == null) return try NativeResult.copyString(ctx.allocator, "");
    defer c.xmlFree.?(v);
    return try NativeResult.copyString(ctx.allocator, v[0..cstrLen(v)]);
}

fn domElementSetAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[1] != .string or args[2] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const qname = args[1].string.bytes();
    const val_z = try dupZ(ctx, args[2].string.bytes());

    var ns_ptr: ?*c.xmlNs = null;
    if (args[0] == .string and args[0].string.bytes().len > 0) {
        const uri_z = try dupZ(ctx, args[0].string.bytes());
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
    const href: [*c]const u8 = if (ns_ptr) |ns| ns.href else null;
    if (c.xmlHasNsProp(node, @ptrCast(local_z.ptr), href)) |existing| tree.rescueChildren(@ptrCast(existing));
    _ = c.xmlSetNsProp(node, ns_ptr, @ptrCast(local_z.ptr), @ptrCast(val_z.ptr));
    return NativeResult.scalar(.null);
}

fn domElementHasAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const ns_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.bytes().len > 0)
        @ptrCast((try dupZ(ctx, args[0].string.bytes())).ptr)
    else
        null;
    const name_z = try dupZ(ctx, args[1].string.bytes());
    const v = c.xmlGetNsProp(node, @ptrCast(name_z.ptr), ns_ptr);
    if (v == null) return NativeResult.scalar(.{ .bool = false });
    c.xmlFree.?(v);
    return NativeResult.scalar(.{ .bool = true });
}

fn domElementRemoveAttributeNS(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const ns_ptr: [*c]const u8 = if (args[0] == .string and args[0].string.bytes().len > 0)
        @ptrCast((try dupZ(ctx, args[0].string.bytes())).ptr)
    else
        null;
    const name_z = try dupZ(ctx, args[1].string.bytes());
    _ = discardAttribute(c.xmlHasNsProp(node, @ptrCast(name_z.ptr), ns_ptr));
    return NativeResult.scalar(.null);
}

fn domElementGetElementsByTagName(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    var list = std.ArrayList(*c.xmlNode).empty;
    defer list.deinit(ctx.allocator);
    var child = node.children;
    while (child != null) : (child = child.*.next) try collectByName(ctx.allocator, child, args[0].string.bytes(), &list);
    return try makeNodeList(ctx, list.items);
}

fn domGetElementsByTagNameNS(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const ns = if (args[0] == .string) args[0].string.bytes() else "*";
    const name = args[1].string.bytes();
    var node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    // for DOMDocument, the wrapping node may not have children walking the doc;
    // start at the root element
    if (node.type == c.XML_DOCUMENT_NODE) {
        const root = c.xmlDocGetRootElement(@ptrCast(node));
        if (root == null) return try makeNodeList(ctx, &.{});
        node = root;
    }
    var list = std.ArrayList(*c.xmlNode).empty;
    defer list.deinit(ctx.allocator);
    try collectByNameNS(ctx.allocator, node, ns, name, &list);
    return try makeNodeList(ctx, list.items);
}

fn domElementGetAttributeNode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const name_z = try dupZ(ctx, args[0].string.bytes());
    const attr = c.xmlHasProp(node, @ptrCast(name_z.ptr));
    if (attr == null) return NativeResult.scalar(.null);
    return NativeResult.borrowed(try wrapNode(ctx, @ptrCast(attr)));
}

// ---------------- DOMCharacterData methods ----------------

fn domCdAppendData(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.null);
    const text_z = try dupZ(ctx, args[0].string.bytes());
    _ = c.xmlNodeAddContent(node, @ptrCast(text_z.ptr));
    return NativeResult.scalar(.null);
}

fn domCdSubstringData(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .int or args[1] != .int) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const node = getNodePtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const content = c.xmlNodeGetContent(node);
    if (content == null) return try NativeResult.copyString(ctx.allocator, "");
    defer c.xmlFree.?(content);
    const slice = content[0..cstrLen(content)];
    const off: usize = if (args[0].int < 0) 0 else @intCast(args[0].int);
    if (off >= slice.len) return try NativeResult.copyString(ctx.allocator, "");
    const cnt: usize = if (args[1].int < 0) 0 else @intCast(args[1].int);
    const end = @min(off + cnt, slice.len);
    return try NativeResult.copyString(ctx.allocator, slice[off..end]);
}

// ---------------- DOMNodeList ----------------

fn makeNodeList(ctx: *NativeContext, nodes: []*c.xmlNode) RuntimeError!NativeResult {
    const list_obj = try ctx.createObject("DOMNodeList");
    const arr = try ctx.createArray();
    for (nodes, 0..) |n, i| {
        const wrapped = try wrapNode(ctx, n);
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, wrapped);
    }
    try list_obj.set(ctx.allocator, "__items", .{ .array = arr });
    try list_obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try list_obj.set(ctx.allocator, "length", .{ .int = @intCast(nodes.len) });
    return NativeResult.borrowed(.{ .object = list_obj });
}

fn nlItems(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__items");
    if (v != .array) return null;
    return v.array;
}

fn domNodeListLength(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arr = nlItems(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(arr.entries.items.len) });
}

fn domNodeListItem(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.null);
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.null);
    const arr = nlItems(obj) orelse return NativeResult.scalar(.null);
    const idx = args[0].int;
    if (idx < 0 or idx >= @as(i64, @intCast(arr.entries.items.len))) return NativeResult.scalar(.null);
    return NativeResult.share(arr.entries.items[@intCast(idx)].value);
}

fn domNodeListCount(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return domNodeListLength(ctx, args);
}

fn domNodeListRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.null);
    obj.set(ctx.allocator, "__pos", .{ .int = 0 }) catch {};
    return NativeResult.scalar(.null);
}

fn domNodeListValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = nlItems(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const pos = obj.get("__pos");
    const p: i64 = if (pos == .int) pos.int else 0;
    return NativeResult.scalar(.{ .bool = p >= 0 and p < @as(i64, @intCast(arr.entries.items.len)) });
}

fn domNodeListCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.null);
    const arr = nlItems(obj) orelse return NativeResult.scalar(.null);
    const pos = obj.get("__pos");
    const p: i64 = if (pos == .int) pos.int else 0;
    if (p < 0 or p >= @as(i64, @intCast(arr.entries.items.len))) return NativeResult.scalar(.null);
    return NativeResult.share(arr.entries.items[@intCast(p)].value);
}

fn domNodeListKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const pos = obj.get("__pos");
    return if (pos == .int) NativeResult.share(pos) else NativeResult.scalar(.{ .int = 0 });
}

fn domNodeListNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.null);
    const pos = obj.get("__pos");
    const p: i64 = if (pos == .int) pos.int else 0;
    obj.set(ctx.allocator, "__pos", .{ .int = p + 1 }) catch {};
    return NativeResult.scalar(.null);
}

fn getThisOf(ctx: *NativeContext) ?*PhpObject {
    const vm = ctx.vm;
    if (vm.frame_count == 0) return null;
    const v = vm.frames[vm.frame_count - 1].vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}


// ---------------- DOMNamedNodeMap ----------------

fn makeNamedNodeMap(ctx: *NativeContext, element: *c.xmlNode) RuntimeError!NativeResult {
    const map_obj = try ctx.createObject("DOMNamedNodeMap");
    const arr = try ctx.createArray();
    const named = try ctx.createArray();
    var attr = element.properties;
    var i: usize = 0;
    while (attr != null) : (attr = attr.*.next) {
        const wrapped = try wrapNode(ctx, @ptrCast(attr));
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, wrapped);
        if (attr.*.name != null) {
            const name = attr.*.name;
            try named.set(ctx.allocator, .{ .string = try dupString(ctx, name[0..cstrLen(name)]) }, wrapped);
        }
        i += 1;
    }
    try map_obj.set(ctx.allocator, "__items", .{ .array = arr });
    try map_obj.set(ctx.allocator, "__named", .{ .array = named });
    try map_obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try map_obj.set(ctx.allocator, "length", .{ .int = @intCast(i) });
    return NativeResult.borrowed(.{ .object = map_obj });
}

fn domNNMGetNamedItem(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.null);
    const named = obj.get("__named");
    if (named != .array) return NativeResult.scalar(.null);
    return NativeResult.share(named.array.get(.{ .string = args[0].string }));
}

fn domNNMItem(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.null);
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.null);
    const items = obj.get("__items");
    if (items != .array) return NativeResult.scalar(.null);
    const idx = args[0].int;
    if (idx < 0 or idx >= @as(i64, @intCast(items.array.entries.items.len))) return NativeResult.scalar(.null);
    return NativeResult.share(items.array.entries.items[@intCast(idx)].value);
}

fn domNNMCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const items = obj.get("__items");
    if (items != .array) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(items.array.entries.items.len) });
}

// ---------------- DOMXPath ----------------

fn domXpathConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__doc", args[0]);
    return NativeResult.scalar(.null);
}

fn domXpathRegisterNamespace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    var ns_map = obj.get("__namespaces");
    if (ns_map != .array) {
        const arr = try ctx.createArray();
        try obj.set(ctx.allocator, "__namespaces", .{ .array = arr });
        ns_map = .{ .array = arr };
    }
    try ns_map.array.set(ctx.allocator, .{ .string = try dupString(ctx, args[0].string.bytes()) }, .{ .string = try dupString(ctx, args[1].string.bytes()) });
    return NativeResult.scalar(.{ .bool = true });
}

fn domXpathQuery(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc_v = obj.get("__doc");
    if (doc_v != .object) return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(doc_v.object) orelse return NativeResult.scalar(.{ .bool = false });

    var context_node: ?*c.xmlNode = null;
    if (args.len > 1 and args[1] == .object) {
        context_node = getNodePtr(args[1].object);
    }

    const xctx = c.xmlXPathNewContext(doc) orelse return NativeResult.scalar(.{ .bool = false });
    defer c.xmlXPathFreeContext(xctx);
    if (context_node) |cn| xctx.*.node = cn;

    // register any user namespaces
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

    if (result.*.type != c.XPATH_NODESET) {
        return try makeNodeList(ctx, &.{});
    }
    const ns = result.*.nodesetval;
    if (ns == null) return try makeNodeList(ctx, &.{});

    return try buildXpathNodeList(ctx, ns);
}

// build a DOMNodeList from an xmlXPath nodeset. namespace pseudo-nodes get
// converted into standalone PhpObjects right away because the underlying
// xmlNs entries are freed when xmlXPathFreeObject runs on this result
fn buildXpathNodeList(ctx: *NativeContext, xset: *c.xmlNodeSet) RuntimeError!NativeResult {
    const list_obj = try ctx.createObject("DOMNodeList");
    const arr = try ctx.createArray();
    var i: usize = 0;
    while (i < @as(usize, @intCast(xset.nodeNr))) : (i += 1) {
        const n = xset.nodeTab[i];
        if (n == null) continue;
        const wrapped = if (n.*.type == c.XML_NAMESPACE_DECL)
            try wrapNamespaceNode(ctx, @ptrCast(n))
        else
            try wrapNode(ctx, n);
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, wrapped);
    }
    try list_obj.set(ctx.allocator, "__items", .{ .array = arr });
    try list_obj.set(ctx.allocator, "__pos", .{ .int = 0 });
    try list_obj.set(ctx.allocator, "length", .{ .int = @intCast(xset.nodeNr) });
    return NativeResult.borrowed(.{ .object = list_obj });
}

fn wrapNamespaceNode(ctx: *NativeContext, ns: *c.xmlNs) !Value {
    const obj = try ctx.createObject("DOMNameSpaceNode");
    try obj.set(ctx.allocator, "__ns_kind", .{ .bool = true });
    if (ns.prefix != null) {
        const slice = ns.prefix[0..cstrLen(ns.prefix)];
        try obj.setCopiedString(ctx.allocator, "__ns_prefix", slice);
    } else {
        try obj.setCopiedString(ctx.allocator, "__ns_prefix", "");
    }
    if (ns.href != null) {
        const slice = ns.href[0..cstrLen(ns.href)];
        try obj.setCopiedString(ctx.allocator, "__ns_href", slice);
    } else {
        try obj.setCopiedString(ctx.allocator, "__ns_href", "");
    }
    return .{ .object = obj };
}

fn domXpathEvaluate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const doc_v = obj.get("__doc");
    if (doc_v != .object) return NativeResult.scalar(.{ .bool = false });
    const doc = getDocPtr(doc_v.object) orelse return NativeResult.scalar(.{ .bool = false });

    var context_node: ?*c.xmlNode = null;
    if (args.len > 1 and args[1] == .object) context_node = getNodePtr(args[1].object);

    const xctx = c.xmlXPathNewContext(doc) orelse return NativeResult.scalar(.{ .bool = false });
    defer c.xmlXPathFreeContext(xctx);
    if (context_node) |cn| xctx.*.node = cn;

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

    switch (result.*.type) {
        c.XPATH_NODESET => {
            const xs = result.*.nodesetval;
            if (xs == null) return try makeNodeList(ctx, &.{});
            return try buildXpathNodeList(ctx, xs);
        },
        c.XPATH_BOOLEAN => return NativeResult.scalar(.{ .bool = result.*.boolval != 0 }),
        c.XPATH_NUMBER => return NativeResult.scalar(.{ .float = result.*.floatval }),
        c.XPATH_STRING => {
            if (result.*.stringval == null) return try NativeResult.copyString(ctx.allocator, "");
            const s = result.*.stringval;
            return try NativeResult.copyString(ctx.allocator, s[0..cstrLen(s)]);
        },
        else => return NativeResult.scalar(.null),
    }
}

// ---------------- registration ----------------

pub fn register(vm: *VM, a: Allocator) !void {
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

    // LibXMLError plain-data class - properties only, no methods. PHP's libxml
    // populates it as the element type returned by libxml_get_errors() /
    // libxml_get_last_error(). LIBXML_ERR_WARNING/ERROR/FATAL constants live
    // alongside it
    const le_def = ClassDef{ .name = "LibXMLError" };
    try vm.classes.put(a, "LibXMLError", le_def);
}

fn registerDocClass(vm: *VM, a: Allocator) !void {
    var def = ClassDef{ .name = "DOMDocument", .parent = "DOMNode", .native_clone = cloneDocHandle, .native_cleanup = cleanupWrapper };
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
    try vm.native_fns.put(a, "DOMDocument::schemaValidateSource", domDocSchemaValidateSource);
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
    var def = ClassDef{ .name = "DOMNode", .native_clone = cloneNodeHandle, .native_cleanup = cleanupWrapper };
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
    var def = ClassDef{ .name = "DOMElement", .native_clone = cloneNodeHandle };
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
        var def = ClassDef{ .name = name, .native_clone = cloneNodeHandle };
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
    var def = ClassDef{ .name = "DOMAttr", .native_clone = cloneNodeHandle };
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

fn domNodeListOffsetExists(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    const obj = getThisOf(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const arr = nlItems(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const idx = Value.toInt(args[0]);
    return NativeResult.scalar(.{ .bool = idx >= 0 and idx < @as(i64, @intCast(arr.entries.items.len)) });
}

fn domNodeListReadOnly(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP's DOMNodeList ArrayAccess is read-only; offsetSet/offsetUnset are
    // no-ops in practice (they throw on some builds but the result is the
    // same: the list isn't mutated). matching that is enough for compat
    return NativeResult.scalar(.null);
}

fn domNodeListGet(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (std.mem.eql(u8, args[0].string.bytes(), "length")) {
        const items = obj.get("__items");
        if (items != .array) return NativeResult.scalar(.{ .int = 0 });
        return NativeResult.scalar(.{ .int = @intCast(items.array.entries.items.len) });
    }
    return NativeResult.scalar(.null);
}

// DOMNamedNodeMap iterates with the attribute name as key (PHP semantics)
// rather than the numeric index used for NodeList
fn domNNMGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const named = obj.get("__named");
    if (named != .array) return NativeResult.scalar(.null);
    const iter_obj = try ctx.createObject("ArrayIterator");
    try iter_obj.set(ctx.allocator, "__data", named);
    try iter_obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try iter_obj.set(ctx.allocator, "__flags", .{ .int = 0 });
    return NativeResult.borrowed(.{ .object = iter_obj });
}

fn domNodeListGetIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const items = obj.get("__items");
    if (items != .array) return NativeResult.scalar(.null);
    const iter_obj = try ctx.createObject("ArrayIterator");
    try iter_obj.set(ctx.allocator, "__data", items);
    try iter_obj.set(ctx.allocator, "__cursor", .{ .int = 0 });
    try iter_obj.set(ctx.allocator, "__flags", .{ .int = 0 });
    return NativeResult.borrowed(.{ .object = iter_obj });
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
    try vm.php_constants.put(a, "LIBXML_DOTTED_VERSION", .{ .string = Value.String.borrowed(std.mem.span(@as([*:0]const u8, c.LIBXML_DOTTED_VERSION))) });
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

fn libxmlUseInternalErrors(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const prev = libxml_internal_errors_enabled;
    if (args.len > 0) {
        switch (args[0]) {
            .bool => |b| libxml_internal_errors_enabled = b,
            .int => |i| libxml_internal_errors_enabled = i != 0,
            else => {},
        }
    }
    return NativeResult.scalar(.{ .bool = prev });
}

fn libxmlClearErrors(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    for (captured_errors.items) |*e| freeCapturedError(e);
    captured_errors.clearRetainingCapacity();
    return NativeResult.scalar(.null);
}

fn buildLibXMLError(ctx: *NativeContext, e: CapturedError) RuntimeError!Value {
    const obj = try ctx.createObject("LibXMLError");
    try obj.set(ctx.allocator, "level", .{ .int = @intCast(e.level) });
    try obj.set(ctx.allocator, "code", .{ .int = @intCast(e.code) });
    try obj.set(ctx.allocator, "column", .{ .int = @intCast(e.column) });
    // libxml appends a trailing space + period to most messages but PHP
    // strips just the trailing newline (already done in handler)
    try obj.setCopiedString(ctx.allocator, "message", e.message);
    if (e.file) |f| {
        try obj.setCopiedString(ctx.allocator, "file", f);
    } else {
        try obj.set(ctx.allocator, "file", .{ .string = Value.String.borrowed("") });
    }
    try obj.set(ctx.allocator, "line", .{ .int = @intCast(e.line) });
    return .{ .object = obj };
}

fn libxmlGetErrors(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (captured_errors.items) |e| {
        try arr.append(ctx.allocator, try buildLibXMLError(ctx, e));
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn libxmlGetLastError(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    if (captured_errors.items.len == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(try buildLibXMLError(ctx, captured_errors.items[captured_errors.items.len - 1]));
}

fn libxmlDisableEntityLoader(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // deprecated in PHP 8.0+ and a noop on modern libxml. accept and return true
    _ = args;
    return NativeResult.scalar(.{ .bool = true });
}

fn libxmlSetExternalEntityLoader(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

// the request-end sweep: wrappers still alive let go of their trees
pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| if (!obj.pooled) detach(obj);
}
