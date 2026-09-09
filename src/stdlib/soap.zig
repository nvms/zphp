const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cInclude("curl/curl.h");
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

pub fn register(vm: *VM, a: Allocator) !void {
    // SoapClient
    {
        var def = ClassDef{ .name = "SoapClient" };
        try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
        try def.methods.put(a, "__soapCall", .{ .name = "__soapCall", .arity = 5 });
        try def.methods.put(a, "__call", .{ .name = "__call", .arity = 2 });
        try def.methods.put(a, "__getLastRequest", .{ .name = "__getLastRequest", .arity = 0 });
        try def.methods.put(a, "__getLastResponse", .{ .name = "__getLastResponse", .arity = 0 });
        try def.methods.put(a, "__getLastRequestHeaders", .{ .name = "__getLastRequestHeaders", .arity = 0 });
        try def.methods.put(a, "__getLastResponseHeaders", .{ .name = "__getLastResponseHeaders", .arity = 0 });
        try def.methods.put(a, "__setLocation", .{ .name = "__setLocation", .arity = 1 });
        try def.methods.put(a, "__setSoapHeaders", .{ .name = "__setSoapHeaders", .arity = 1 });
        try def.methods.put(a, "__getFunctions", .{ .name = "__getFunctions", .arity = 0 });
        try def.methods.put(a, "__getTypes", .{ .name = "__getTypes", .arity = 0 });
        try def.methods.put(a, "__setCookie", .{ .name = "__setCookie", .arity = 2 });
        try def.methods.put(a, "__getCookies", .{ .name = "__getCookies", .arity = 0 });
        try vm.classes.put(a, "SoapClient", def);
        try vm.native_fns.put(a, "SoapClient::__construct", soapClientConstruct);
        try vm.native_fns.put(a, "SoapClient::__soapCall", soapClientCall);
        try vm.native_fns.put(a, "SoapClient::__call", soapClientMagicCall);
        try vm.native_fns.put(a, "SoapClient::__getLastRequest", soapClientGetLastRequest);
        try vm.native_fns.put(a, "SoapClient::__getLastResponse", soapClientGetLastResponse);
        try vm.native_fns.put(a, "SoapClient::__getLastRequestHeaders", soapClientGetLastRequestHeaders);
        try vm.native_fns.put(a, "SoapClient::__getLastResponseHeaders", soapClientGetLastResponseHeaders);
        try vm.native_fns.put(a, "SoapClient::__setLocation", soapClientSetLocation);
        try vm.native_fns.put(a, "SoapClient::__setSoapHeaders", soapClientSetSoapHeaders);
        try vm.native_fns.put(a, "SoapClient::__getFunctions", soapClientGetFunctions);
        try vm.native_fns.put(a, "SoapClient::__getTypes", soapClientGetTypes);
        try vm.native_fns.put(a, "SoapClient::__setCookie", soapClientSetCookie);
        try vm.native_fns.put(a, "SoapClient::__getCookies", soapClientGetCookies);
    }

    // SoapServer
    {
        var def = ClassDef{ .name = "SoapServer" };
        try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
        try def.methods.put(a, "addFunction", .{ .name = "addFunction", .arity = 1 });
        try def.methods.put(a, "setObject", .{ .name = "setObject", .arity = 1 });
        try def.methods.put(a, "setClass", .{ .name = "setClass", .arity = 1 });
        try def.methods.put(a, "handle", .{ .name = "handle", .arity = 1 });
        try def.methods.put(a, "fault", .{ .name = "fault", .arity = 4 });
        try def.methods.put(a, "addSoapHeader", .{ .name = "addSoapHeader", .arity = 1 });
        try def.methods.put(a, "getFunctions", .{ .name = "getFunctions", .arity = 0 });
        try def.methods.put(a, "setPersistence", .{ .name = "setPersistence", .arity = 1 });
        try vm.classes.put(a, "SoapServer", def);
        try vm.native_fns.put(a, "SoapServer::__construct", soapServerConstruct);
        try vm.native_fns.put(a, "SoapServer::addFunction", soapServerAddFunction);
        try vm.native_fns.put(a, "SoapServer::setObject", soapServerSetObject);
        try vm.native_fns.put(a, "SoapServer::setClass", soapServerSetClass);
        try vm.native_fns.put(a, "SoapServer::handle", soapServerHandle);
        try vm.native_fns.put(a, "SoapServer::fault", soapServerFault);
        try vm.native_fns.put(a, "SoapServer::addSoapHeader", soapServerAddSoapHeader);
        try vm.native_fns.put(a, "SoapServer::getFunctions", soapServerGetFunctions);
        try vm.native_fns.put(a, "SoapServer::setPersistence", soapServerSetPersistence);
    }

    // SoapHeader
    {
        var def = ClassDef{ .name = "SoapHeader" };
        try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 5 });
        try vm.classes.put(a, "SoapHeader", def);
        try vm.native_fns.put(a, "SoapHeader::__construct", soapHeaderConstruct);
    }

    // SoapVar
    {
        var def = ClassDef{ .name = "SoapVar" };
        try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 5 });
        try vm.classes.put(a, "SoapVar", def);
        try vm.native_fns.put(a, "SoapVar::__construct", soapVarConstruct);
    }

    // SoapParam
    {
        var def = ClassDef{ .name = "SoapParam" };
        try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
        try vm.classes.put(a, "SoapParam", def);
        try vm.native_fns.put(a, "SoapParam::__construct", soapParamConstruct);
    }

    // SoapFault - extends Exception
    {
        var def = ClassDef{ .name = "SoapFault" };
        def.parent = "Exception";
        try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 6 });
        try def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
        try vm.classes.put(a, "SoapFault", def);
        try vm.native_fns.put(a, "SoapFault::__construct", soapFaultConstruct);
        try vm.native_fns.put(a, "SoapFault::__toString", soapFaultToString);
    }
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    if (ctx.vm.frame_count == 0) return null;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getOpt(opts: ?*PhpArray, key: []const u8) Value {
    if (opts == null) return .null;
    return opts.?.get(.{ .string = Value.String.borrowed(key) });
}

fn loadText(allocator: Allocator, source: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, source, "file://")) return std.fs.cwd().readFileAlloc(allocator, source[7..], 16 * 1024 * 1024);
    return std.fs.cwd().readFileAlloc(allocator, source, 16 * 1024 * 1024);
}

fn localName(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, name, ':')) |i| name[i + 1 ..] else name;
}

fn nodeName(node: *c.xmlNode) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(node.name)));
}

fn attrValue(allocator: Allocator, node: *c.xmlNode, name: [*:0]const u8) !?[]u8 {
    const raw = c.xmlGetProp(node, @ptrCast(name)) orelse return null;
    defer c.xmlFree.?(raw);
    return try allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(raw))));
}

fn parseWsdl(ctx: *NativeContext, obj: *PhpObject, source: []const u8) RuntimeError!void {
    const bytes = loadText(ctx.allocator, source) catch {
        try ctx.vm.setPendingException("SoapFault", "SOAP-ERROR: Parsing WSDL: Couldn't load from source");
        return;
    };
    defer ctx.allocator.free(bytes);
    const doc = c.xmlReadMemory(bytes.ptr, @intCast(bytes.len), null, null, c.XML_PARSE_NONET | c.XML_PARSE_NOBLANKS) orelse {
        try ctx.vm.setPendingException("SoapFault", "SOAP-ERROR: Parsing WSDL failed");
        return;
    };
    defer c.xmlFreeDoc(doc);
    const root: *c.xmlNode = @ptrCast(c.xmlDocGetRootElement(doc) orelse return);
    const target_ns = try attrValue(ctx.allocator, root, "targetNamespace");
    defer if (target_ns) |v| ctx.allocator.free(v);
    if (target_ns) |v| {
        const owned = try ctx.allocator.dupe(u8, v);
        try ctx.strings.append(ctx.allocator, owned);
        try obj.set(ctx.allocator, "__uri", .{ .string = Value.String.borrowed(owned) });
    }
    const functions = try ctx.createArray();
    const types = try ctx.createArray();
    var child: ?*c.xmlNode = @ptrCast(root.children);
    while (child) |n| : (child = @ptrCast(n.next)) {
        if (n.type != c.XML_ELEMENT_NODE) continue;
        const lname = localName(nodeName(n));
        if (std.mem.eql(u8, lname, "service")) {
            var port: ?*c.xmlNode = @ptrCast(n.children);
            while (port) |pn| : (port = @ptrCast(pn.next)) {
                var ext: ?*c.xmlNode = @ptrCast(pn.children);
                while (ext) |en| : (ext = @ptrCast(en.next)) {
                    if (std.mem.eql(u8, localName(nodeName(en)), "address")) {
                        const loc = try attrValue(ctx.allocator, en, "location");
                        defer if (loc) |v| ctx.allocator.free(v);
                        if (loc) |v| {
                            const owned = try ctx.allocator.dupe(u8, v);
                            try ctx.strings.append(ctx.allocator, owned);
                            try obj.set(ctx.allocator, "__location", .{ .string = Value.String.borrowed(owned) });
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, lname, "portType")) {
            var op: ?*c.xmlNode = @ptrCast(n.children);
            while (op) |on| : (op = @ptrCast(on.next)) {
                if (!std.mem.eql(u8, localName(nodeName(on)), "operation")) continue;
                const name = try attrValue(ctx.allocator, on, "name");
                defer if (name) |v| ctx.allocator.free(v);
                if (name) |v| {
                    const sig = try std.fmt.allocPrint(ctx.allocator, "void {s}()", .{v});
                    try ctx.strings.append(ctx.allocator, sig);
                    try functions.set(ctx.allocator, .{ .int = functions.next_int_key }, .{ .string = Value.String.borrowed(sig) });
                }
            }
        } else if (std.mem.eql(u8, lname, "types")) {
            var schema: ?*c.xmlNode = @ptrCast(n.children);
            while (schema) |sn| : (schema = @ptrCast(sn.next)) {
                var typ: ?*c.xmlNode = @ptrCast(sn.children);
                while (typ) |tn| : (typ = @ptrCast(tn.next)) {
                    if (!std.mem.eql(u8, localName(nodeName(tn)), "complexType")) continue;
                    const name = try attrValue(ctx.allocator, tn, "name");
                    defer if (name) |v| ctx.allocator.free(v);
                    if (name) |v| {
                        var decl = std.ArrayListUnmanaged(u8){};
                        try decl.appendSlice(ctx.allocator, "struct ");
                        try decl.appendSlice(ctx.allocator, v);
                        try decl.appendSlice(ctx.allocator, " {\n");
                        var seq: ?*c.xmlNode = @ptrCast(tn.children);
                        while (seq) |qn| : (seq = @ptrCast(qn.next)) {
                            var elem: ?*c.xmlNode = @ptrCast(qn.children);
                            while (elem) |en| : (elem = @ptrCast(en.next)) {
                                if (!std.mem.eql(u8, localName(nodeName(en)), "element")) continue;
                                const field = try attrValue(ctx.allocator, en, "name");
                                defer if (field) |fv| ctx.allocator.free(fv);
                                const xtype = try attrValue(ctx.allocator, en, "type");
                                defer if (xtype) |tv| ctx.allocator.free(tv);
                                if (field) |fv| {
                                    const php_type = if (xtype) |tv| blk: {
                                        const t = localName(tv);
                                        if (std.mem.eql(u8, t, "int") or std.mem.eql(u8, t, "integer")) break :blk "int";
                                        if (std.mem.eql(u8, t, "string")) break :blk "string";
                                        if (std.mem.eql(u8, t, "boolean")) break :blk "boolean";
                                        if (std.mem.eql(u8, t, "float") or std.mem.eql(u8, t, "double")) break :blk "float";
                                        break :blk t;
                                    } else "mixed";
                                    try decl.appendSlice(ctx.allocator, " ");
                                    try decl.appendSlice(ctx.allocator, php_type);
                                    try decl.appendSlice(ctx.allocator, " ");
                                    try decl.appendSlice(ctx.allocator, fv);
                                    try decl.appendSlice(ctx.allocator, ";\n");
                                }
                            }
                        }
                        try decl.appendSlice(ctx.allocator, "}");
                        const owned = try decl.toOwnedSlice(ctx.allocator);
                        try ctx.strings.append(ctx.allocator, owned);
                        try types.set(ctx.allocator, .{ .int = types.next_int_key }, .{ .string = Value.String.borrowed(owned) });
                    }
                }
            }
        }
    }
    try obj.set(ctx.allocator, "__functions", .{ .array = functions });
    try obj.set(ctx.allocator, "__types", .{ .array = types });
}

fn soapClientConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);

    const wsdl = if (args.len > 0) args[0] else .null;
    const opts: ?*PhpArray = if (args.len > 1 and args[1] == .array) args[1].array else null;

    try obj.set(ctx.allocator, "__wsdl", wsdl);
    try obj.set(ctx.allocator, "__options", if (opts != null) Value{ .array = opts.? } else .null);

    // for non-WSDL mode, location and uri come from options
    const loc = getOpt(opts, "location");
    const uri = getOpt(opts, "uri");
    try obj.set(ctx.allocator, "__location", loc);
    try obj.set(ctx.allocator, "__uri", uri);

    const soap_version = getOpt(opts, "soap_version");
    const ver: i64 = if (soap_version == .int) soap_version.int else 1; // SOAP_1_1
    try obj.set(ctx.allocator, "__soap_version", .{ .int = ver });

    try obj.set(ctx.allocator, "__last_request", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__last_response", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__last_request_headers", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__last_response_headers", .{ .string = Value.String.borrowed("") });
    try obj.set(ctx.allocator, "__headers", .{ .array = try ctx.createArray() });
    try obj.set(ctx.allocator, "__cookies", .{ .array = try ctx.createArray() });
    try obj.set(ctx.allocator, "__functions", .{ .array = try ctx.createArray() });
    try obj.set(ctx.allocator, "__types", .{ .array = try ctx.createArray() });
    if (wsdl == .string) try parseWsdl(ctx, obj, wsdl.string.bytes());

    if (wsdl != .null and wsdl != .string) {
        // PHP throws SoapFault here. we accept null only for non-WSDL.
    }
    return NativeResult.scalar(.null);
}

fn xmlEscape(allocator: Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);
    for (s) |ch| switch (ch) {
        '<' => try out.appendSlice(allocator, "&lt;"),
        '>' => try out.appendSlice(allocator, "&gt;"),
        '&' => try out.appendSlice(allocator, "&amp;"),
        '"' => try out.appendSlice(allocator, "&quot;"),
        '\'' => try out.appendSlice(allocator, "&apos;"),
        else => try out.append(allocator, ch),
    };
    return try out.toOwnedSlice(allocator);
}

fn appendValue(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), tag: []const u8, val: Value) RuntimeError!void {
    try out.appendSlice(ctx.allocator, "<");
    try out.appendSlice(ctx.allocator, tag);
    switch (val) {
        .null => {
            try out.appendSlice(ctx.allocator, " xsi:nil=\"true\"/>");
            return;
        },
        .int => |i| {
            try out.appendSlice(ctx.allocator, " xsi:type=\"xsd:int\">");
            const s = try std.fmt.allocPrint(ctx.allocator, "{d}", .{i});
            defer ctx.allocator.free(s);
            try out.appendSlice(ctx.allocator, s);
        },
        .float => |f| {
            try out.appendSlice(ctx.allocator, " xsi:type=\"xsd:double\">");
            const s = try std.fmt.allocPrint(ctx.allocator, "{d}", .{f});
            defer ctx.allocator.free(s);
            try out.appendSlice(ctx.allocator, s);
        },
        .bool => |b| {
            try out.appendSlice(ctx.allocator, " xsi:type=\"xsd:boolean\">");
            try out.appendSlice(ctx.allocator, if (b) "true" else "false");
        },
        .string => |s| {
            try out.appendSlice(ctx.allocator, " xsi:type=\"xsd:string\">");
            const esc = try xmlEscape(ctx.allocator, s.bytes());
            defer ctx.allocator.free(esc);
            try out.appendSlice(ctx.allocator, esc);
        },
        .array => |arr| {
            try out.appendSlice(ctx.allocator, ">");
            for (arr.entries.items) |entry| {
                const child_tag = switch (entry.key) {
                    .string => |s| s.bytes(),
                    .int => "item",
                };
                try appendValue(ctx, out, child_tag, entry.value);
            }
        },
        .object => |obj| {
            try out.appendSlice(ctx.allocator, ">");
            var it = obj.properties.iterator();
            while (it.next()) |entry| try appendValue(ctx, out, entry.key_ptr.*, entry.value_ptr.*);
        },
        else => try out.appendSlice(ctx.allocator, ">"),
    }
    try out.appendSlice(ctx.allocator, "</");
    try out.appendSlice(ctx.allocator, tag);
    try out.appendSlice(ctx.allocator, ">");
}

fn appendSoapHeader(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), header: *PhpObject, index: usize) RuntimeError!void {
    const ns = header.get("namespace");
    const name = header.get("name");
    if (ns != .string or name != .string) return;
    const prefix = try std.fmt.allocPrint(ctx.allocator, "ns{d}", .{index + 2});
    defer ctx.allocator.free(prefix);
    try out.appendSlice(ctx.allocator, "<");
    try out.appendSlice(ctx.allocator, prefix);
    try out.appendSlice(ctx.allocator, ":");
    try out.appendSlice(ctx.allocator, name.string.bytes());
    try out.appendSlice(ctx.allocator, " xmlns:");
    try out.appendSlice(ctx.allocator, prefix);
    try out.appendSlice(ctx.allocator, "=\"");
    const ns_esc = try xmlEscape(ctx.allocator, ns.string.bytes());
    defer ctx.allocator.free(ns_esc);
    try out.appendSlice(ctx.allocator, ns_esc);
    try out.appendSlice(ctx.allocator, "\"");
    const must = header.get("mustUnderstand");
    if (must == .bool and must.bool) try out.appendSlice(ctx.allocator, " SOAP-ENV:mustUnderstand=\"1\"");
    try out.appendSlice(ctx.allocator, ">");
    const data = header.get("data");
    if (data != .null) {
        const esc = try xmlEscape(ctx.allocator, if (data == .string) data.string.bytes() else "");
        defer ctx.allocator.free(esc);
        try out.appendSlice(ctx.allocator, esc);
    }
    try out.appendSlice(ctx.allocator, "</");
    try out.appendSlice(ctx.allocator, prefix);
    try out.appendSlice(ctx.allocator, ":");
    try out.appendSlice(ctx.allocator, name.string.bytes());
    try out.appendSlice(ctx.allocator, ">");
}

fn buildEnvelope(ctx: *NativeContext, client: *PhpObject, method: []const u8, uri: []const u8, args_array: *PhpArray) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(ctx.allocator);
    try out.appendSlice(ctx.allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ns1="
    );
    const uri_esc = try xmlEscape(ctx.allocator, uri);
    defer ctx.allocator.free(uri_esc);
    try out.appendSlice(ctx.allocator, uri_esc);
    try out.appendSlice(ctx.allocator, "\">");
    const headers = client.get("__headers");
    if (headers == .object or headers == .array) {
        try out.appendSlice(ctx.allocator, "<SOAP-ENV:Header>");
        if (headers == .object) {
            try appendSoapHeader(ctx, &out, headers.object, 0);
        } else {
            for (headers.array.entries.items, 0..) |entry, i| if (entry.value == .object) try appendSoapHeader(ctx, &out, entry.value.object, i);
        }
        try out.appendSlice(ctx.allocator, "</SOAP-ENV:Header>");
    }
    try out.appendSlice(ctx.allocator, "<SOAP-ENV:Body><ns1:");
    try out.appendSlice(ctx.allocator, method);
    try out.appendSlice(ctx.allocator, ">");
    for (args_array.entries.items, 0..) |entry, i| {
        var tag_buf: [64]u8 = undefined;
        const tag = switch (entry.key) {
            .string => |s| s.bytes(),
            .int => try std.fmt.bufPrint(&tag_buf, "param{d}", .{i}),
        };
        try appendValue(ctx, &out, tag, entry.value);
    }
    try out.appendSlice(ctx.allocator, "</ns1:");
    try out.appendSlice(ctx.allocator, method);
    try out.appendSlice(ctx.allocator, "></SOAP-ENV:Body></SOAP-ENV:Envelope>");
    return try out.toOwnedSlice(ctx.allocator);
}

const HttpResponse = struct { body: []u8, headers: []u8, status: c_long };

fn writeCb(ptr: [*c]u8, size: usize, nmemb: usize, ud: ?*anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const buf: *std.ArrayListUnmanaged(u8) = @ptrCast(@alignCast(ud.?));
    const gpa = std.heap.c_allocator;
    buf.appendSlice(gpa, ptr[0..total]) catch return 0;
    return total;
}

fn httpPostSoap(allocator: Allocator, location: []const u8, action: []const u8, body: []const u8) !HttpResponse {
    const handle = c.curl_easy_init() orelse return error.CurlInit;
    defer c.curl_easy_cleanup(handle);

    const loc_z = try allocator.dupeZ(u8, location);
    defer allocator.free(loc_z);
    _ = c.curl_easy_setopt(handle, c.CURLOPT_URL, loc_z.ptr);
    _ = c.curl_easy_setopt(handle, c.CURLOPT_POST, @as(c_long, 1));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDS, body.ptr);
    _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(body.len)));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_TIMEOUT, @as(c_long, 30));

    var resp_buf = std.ArrayListUnmanaged(u8){};
    var hdr_buf = std.ArrayListUnmanaged(u8){};
    errdefer resp_buf.deinit(std.heap.c_allocator);
    errdefer hdr_buf.deinit(std.heap.c_allocator);

    _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, writeCb);
    _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, &resp_buf);
    _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERFUNCTION, writeCb);
    _ = c.curl_easy_setopt(handle, c.CURLOPT_HEADERDATA, &hdr_buf);

    var headers: ?*c.curl_slist = null;
    const ct = try allocator.dupeZ(u8, "Content-Type: text/xml; charset=utf-8");
    defer allocator.free(ct);
    headers = c.curl_slist_append(headers, ct.ptr);
    const action_hdr = try std.fmt.allocPrintSentinel(allocator, "SOAPAction: \"{s}\"", .{action}, 0);
    defer allocator.free(action_hdr);
    headers = c.curl_slist_append(headers, action_hdr.ptr);
    defer c.curl_slist_free_all(headers);
    _ = c.curl_easy_setopt(handle, c.CURLOPT_HTTPHEADER, headers);

    const rc = c.curl_easy_perform(handle);
    if (rc != c.CURLE_OK) return error.CurlPerform;

    var status: c_long = 0;
    _ = c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &status);

    return .{
        .body = try allocator.dupe(u8, resp_buf.items),
        .headers = try allocator.dupe(u8, hdr_buf.items),
        .status = status,
    };
}

fn extractBetween(haystack: []const u8, open: []const u8, close: []const u8) ?[]const u8 {
    const o = std.mem.indexOf(u8, haystack, open) orelse return null;
    const after_o = o + open.len;
    const c_idx = std.mem.indexOfPos(u8, haystack, after_o, close) orelse return null;
    return haystack[after_o..c_idx];
}

// best-effort SOAP response parser: returns innermost text content from the
// response body, or an array of named children if the response has structure.
fn parseSoapResponse(ctx: *NativeContext, xml: []const u8) RuntimeError!NativeResult {
    // find <SOAP-ENV:Body> or <soap:Body> or any *:Body
    var body_start: ?usize = null;
    var body_end: ?usize = null;
    var i: usize = 0;
    while (i < xml.len) {
        if (xml[i] == '<') {
            const close = std.mem.indexOfScalarPos(u8, xml, i, '>') orelse break;
            const tag_content = xml[i + 1 .. close];
            // tag could be "soap:Body" or "Body" or "SOAP-ENV:Body"
            if (std.mem.endsWith(u8, tag_content, "Body") or std.mem.indexOf(u8, tag_content, ":Body ") != null or std.mem.indexOf(u8, tag_content, ":Body>") != null) {
                if (body_start == null) {
                    body_start = close + 1;
                } else {
                    body_end = i;
                }
            } else if (tag_content.len > 0 and tag_content[0] == '/' and std.mem.endsWith(u8, tag_content, "Body")) {
                body_end = i;
            }
            i = close + 1;
        } else i += 1;
    }

    if (body_start == null) {
        return try NativeResult.copyString(ctx.allocator, xml);
    }

    const body = xml[body_start.?..(body_end orelse xml.len)];

    // check for Fault
    if (std.mem.indexOf(u8, body, "Fault") != null) {
        const code = extractBetween(body, "<faultcode>", "</faultcode>") orelse "Server";
        const str = extractBetween(body, "<faultstring>", "</faultstring>") orelse "SOAP fault";
        const owned_code = try ctx.allocator.dupe(u8, code);
        const owned_str = try ctx.allocator.dupe(u8, str);
        try ctx.strings.append(ctx.allocator, owned_code);
        try ctx.strings.append(ctx.allocator, owned_str);
        try ctx.vm.setPendingException("SoapFault", owned_str);
        return NativeResult.scalar(.{ .bool = false });
    }

    // first element inside Body is the response method; its children are the result fields
    // skip whitespace then find first element
    var p: usize = 0;
    while (p < body.len and std.ascii.isWhitespace(body[p])) p += 1;
    if (p >= body.len or body[p] != '<') {
        return try NativeResult.copyString(ctx.allocator, body);
    }
    // skip past response element tag
    const tag_close = std.mem.indexOfScalarPos(u8, body, p, '>') orelse return NativeResult.scalar(.null);
    const inner_start = tag_close + 1;
    // find matching close - approximate by looking for </tag>
    var tag_name_end = p + 1;
    while (tag_name_end < tag_close and body[tag_name_end] != ' ' and body[tag_name_end] != '>') tag_name_end += 1;
    const tag_name = body[p + 1 .. tag_name_end];
    var close_buf: [256]u8 = undefined;
    const close_tag = std.fmt.bufPrint(&close_buf, "</{s}>", .{tag_name}) catch return NativeResult.scalar(.null);
    const inner_end = std.mem.indexOfPos(u8, body, inner_start, close_tag) orelse return NativeResult.scalar(.null);
    const inner = body[inner_start..inner_end];

    // parse first child of inner (the result) - many SOAP responses are <Foo><return>value</return></Foo>
    var rp: usize = 0;
    while (rp < inner.len and std.ascii.isWhitespace(inner[rp])) rp += 1;
    if (rp >= inner.len or inner[rp] != '<') {
        // no children - return inner trimmed text
        var end = inner.len;
        while (end > 0 and std.ascii.isWhitespace(inner[end - 1])) end -= 1;
        return try NativeResult.copyString(ctx.allocator, inner[rp..end]);
    }
    const child_close = std.mem.indexOfScalarPos(u8, inner, rp, '>') orelse return NativeResult.scalar(.null);
    var child_name_end = rp + 1;
    while (child_name_end < child_close and inner[child_name_end] != ' ' and inner[child_name_end] != '>') child_name_end += 1;
    const child_name = inner[rp + 1 .. child_name_end];
    var ccbuf: [256]u8 = undefined;
    const child_close_tag = std.fmt.bufPrint(&ccbuf, "</{s}>", .{child_name}) catch return NativeResult.scalar(.null);
    const child_inner_start = child_close + 1;
    const child_inner_end = std.mem.indexOfPos(u8, inner, child_inner_start, child_close_tag) orelse return NativeResult.scalar(.null);
    const text = inner[child_inner_start..child_inner_end];

    // try to coerce numeric
    if (text.len > 0) {
        if (std.fmt.parseInt(i64, text, 10)) |n| return NativeResult.scalar(.{ .int = n }) else |_| {}
        if (std.fmt.parseFloat(f64, text)) |f| return NativeResult.scalar(.{ .float = f }) else |_| {}
    }
    return try NativeResult.copyString(ctx.allocator, text);
}

fn soapClientCall(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 2 or args[0] != .string or args[1] != .array) return NativeResult.scalar(.null);
    const method = args[0].string.bytes();
    const args_arr = args[1].array;

    const loc_v = obj.get("__location");
    const uri_v = obj.get("__uri");
    if (loc_v != .string or uri_v != .string) {
        try ctx.vm.setPendingException("SoapFault", "SoapClient requires location and uri options for non-WSDL calls");
        return NativeResult.scalar(.{ .bool = false });
    }
    const location = loc_v.string.bytes();
    const uri = uri_v.string.bytes();

    const envelope = buildEnvelope(ctx, obj, method, uri, args_arr) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return NativeResult.scalar(.null),
    };
    defer ctx.allocator.free(envelope);

    var action_buf: [512]u8 = undefined;
    const action = std.fmt.bufPrint(&action_buf, "{s}#{s}", .{ uri, method }) catch return NativeResult.scalar(.null);

    const env_owned = try ctx.allocator.dupe(u8, envelope);
    try ctx.strings.append(ctx.allocator, env_owned);
    try obj.set(ctx.allocator, "__last_request", .{ .string = Value.String.borrowed(env_owned) });

    const resp = httpPostSoap(ctx.allocator, location, action, envelope) catch {
        try ctx.vm.setPendingException("SoapFault", "SOAP HTTP request failed");
        return NativeResult.scalar(.{ .bool = false });
    };
    defer ctx.allocator.free(resp.body);
    defer ctx.allocator.free(resp.headers);

    const resp_owned = try ctx.allocator.dupe(u8, resp.body);
    try ctx.strings.append(ctx.allocator, resp_owned);
    try obj.set(ctx.allocator, "__last_response", .{ .string = Value.String.borrowed(resp_owned) });
    const rh_owned = try ctx.allocator.dupe(u8, resp.headers);
    try ctx.strings.append(ctx.allocator, rh_owned);
    try obj.set(ctx.allocator, "__last_response_headers", .{ .string = Value.String.borrowed(rh_owned) });

    return try parseSoapResponse(ctx, resp.body);
}

fn soapClientMagicCall(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    // signature: __call($name, $arguments) - delegate to __soapCall
    return try soapClientCall(ctx, args);
}

fn soapClientGetLastRequest(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(o.get("__last_request"));
}
fn soapClientGetLastResponse(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(o.get("__last_response"));
}
fn soapClientGetLastRequestHeaders(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(o.get("__last_request_headers"));
}
fn soapClientGetLastResponseHeaders(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(o.get("__last_response_headers"));
}
fn soapClientSetLocation(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const prev = o.get("__location");
    try o.set(ctx.allocator, "__location", args[0]);
    return if (o.get("__wsdl") == .string) NativeResult.scalar(.null) else NativeResult.share(prev);
}
fn soapClientSetSoapHeaders(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    try o.set(ctx.allocator, "__headers", args[0]);
    return NativeResult.scalar(.{ .bool = true });
}
fn soapClientGetFunctions(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(o.get("__functions"));
}
fn soapClientGetTypes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(o.get("__types"));
}
fn soapClientSetCookie(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const cookies_v = o.get("__cookies");
    if (cookies_v != .array) return NativeResult.scalar(.null);
    if (args[0] != .string) return NativeResult.scalar(.null);
    // PHP stores each cookie as a 3-element array: [value, autodelete, path].
    // a single arg deletes the cookie - matches PHP's __setCookie(name) semantic
    if (args.len == 1) {
        try cookies_v.array.set(ctx.allocator, .{ .string = Value.String.borrowed(args[0].string.bytes()) }, .null);
        return NativeResult.scalar(.null);
    }
    const inner = try ctx.createArray();
    try inner.set(ctx.allocator, .{ .int = 0 }, args[1]);
    try cookies_v.array.set(ctx.allocator, .{ .string = Value.String.borrowed(args[0].string.bytes()) }, .{ .array = inner });
    return NativeResult.scalar(.null);
}
fn soapClientGetCookies(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const o = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(o.get("__cookies"));
}

// SoapServer stubs - functional outline. real-world server use is rare from PHP scripts
fn soapServerConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const wsdl = if (args.len > 0) args[0] else .null;
    try obj.set(ctx.allocator, "__wsdl", wsdl);
    try obj.set(ctx.allocator, "__functions", .{ .array = try ctx.createArray() });
    try obj.set(ctx.allocator, "__class", .null);
    try obj.set(ctx.allocator, "__object", .null);
    try obj.set(ctx.allocator, "__response_headers", .{ .array = try ctx.createArray() });
    // the response namespace (ns1) comes from options['uri'] in non-WSDL mode
    var uri: Value = .null;
    if (args.len > 1 and args[1] == .array) {
        const u = args[1].array.get(.{ .string = Value.String.borrowed("uri") });
        if (u == .string) uri = u;
    }
    try obj.set(ctx.allocator, "__uri", uri);
    return NativeResult.scalar(.null);
}
fn soapServerAddFunction(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    const fns_v = obj.get("__functions");
    if (fns_v != .array) return NativeResult.scalar(.{ .bool = false });
    if (args[0] == .string) {
        try fns_v.array.set(ctx.allocator, .{ .int = fns_v.array.next_int_key }, args[0]);
    } else if (args[0] == .array) {
        for (args[0].array.entries.items) |e| {
            try fns_v.array.set(ctx.allocator, .{ .int = fns_v.array.next_int_key }, e.value);
        }
    }
    return NativeResult.scalar(.{ .bool = true });
}
fn soapServerSetObject(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    try obj.set(ctx.allocator, "__object", args[0]);
    return NativeResult.scalar(.{ .bool = true });
}
fn soapServerSetClass(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    try obj.set(ctx.allocator, "__class", args[0]);
    return NativeResult.scalar(.{ .bool = true });
}
fn xmlUnescape(allocator: Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (std.mem.startsWith(u8, s[i..], "&amp;")) {
                try out.append(allocator, '&');
                i += 5;
                continue;
            } else if (std.mem.startsWith(u8, s[i..], "&lt;")) {
                try out.append(allocator, '<');
                i += 4;
                continue;
            } else if (std.mem.startsWith(u8, s[i..], "&gt;")) {
                try out.append(allocator, '>');
                i += 4;
                continue;
            } else if (std.mem.startsWith(u8, s[i..], "&quot;")) {
                try out.append(allocator, '"');
                i += 6;
                continue;
            } else if (std.mem.startsWith(u8, s[i..], "&apos;")) {
                try out.append(allocator, '\'');
                i += 6;
                continue;
            }
        }
        try out.append(allocator, s[i]);
        i += 1;
    }
    return try out.toOwnedSlice(allocator);
}

// encode a return value as PHP SoapServer does: a typed <return> element.
// server-mode uses xsd:float (the client request path's appendValue uses
// xsd:double - they genuinely differ, so this is separate)
fn isList(arr: *PhpArray) bool {
    for (arr.entries.items, 0..) |entry, i| if (entry.key != .int or entry.key.int != i) return false;
    return true;
}

fn encodeTypedValue(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), tag: []const u8, val: Value) RuntimeError!void {
    const a = ctx.allocator;
    try out.appendSlice(a, "<");
    try out.appendSlice(a, tag);
    switch (val) {
        .null => try out.appendSlice(a, " xsi:nil=\"true\"/>"),
        .int => |i| {
            const s = try std.fmt.allocPrint(a, "{d}", .{i});
            defer a.free(s);
            try out.appendSlice(a, " xsi:type=\"xsd:int\">");
            try out.appendSlice(a, s);
            try out.appendSlice(a, "</");
            try out.appendSlice(a, tag);
            try out.appendSlice(a, ">");
        },
        .float => |f| {
            const s = try std.fmt.allocPrint(a, "{d}", .{f});
            defer a.free(s);
            try out.appendSlice(a, " xsi:type=\"xsd:float\">");
            try out.appendSlice(a, s);
            try out.appendSlice(a, "</");
            try out.appendSlice(a, tag);
            try out.appendSlice(a, ">");
        },
        .bool => |b| {
            try out.appendSlice(a, " xsi:type=\"xsd:boolean\">");
            try out.appendSlice(a, if (b) "true" else "false");
            try out.appendSlice(a, "</");
            try out.appendSlice(a, tag);
            try out.appendSlice(a, ">");
        },
        .string => |s| {
            const esc = try xmlEscape(a, s.bytes());
            defer a.free(esc);
            try out.appendSlice(a, " xsi:type=\"xsd:string\">");
            try out.appendSlice(a, esc);
            try out.appendSlice(a, "</");
            try out.appendSlice(a, tag);
            try out.appendSlice(a, ">");
        },
        .array => |arr| {
            if (isList(arr)) {
                var item_type: []const u8 = "anyType";
                if (arr.entries.items.len > 0) item_type = switch (arr.entries.items[0].value) {
                    .int => "int",
                    .float => "float",
                    .bool => "boolean",
                    .string => "string",
                    else => "anyType",
                };
                const count = try std.fmt.allocPrint(a, " SOAP-ENC:arrayType=\"xsd:{s}[{d}]\" xsi:type=\"SOAP-ENC:Array\">", .{ item_type, arr.entries.items.len });
                defer a.free(count);
                try out.appendSlice(a, count);
                for (arr.entries.items) |entry| try encodeTypedValue(ctx, out, "item", entry.value);
            } else {
                try out.appendSlice(a, " xsi:type=\"ns2:Map\">");
                for (arr.entries.items) |entry| {
                    try out.appendSlice(a, "<item>");
                    const key: Value = switch (entry.key) {
                        .string => |s| .{ .string = s },
                        .int => |i| .{ .int = i },
                    };
                    try encodeTypedValue(ctx, out, "key", key);
                    try encodeTypedValue(ctx, out, "value", entry.value);
                    try out.appendSlice(a, "</item>");
                }
            }
            try out.appendSlice(a, "</");
            try out.appendSlice(a, tag);
            try out.appendSlice(a, ">");
        },
        .object => |obj| {
            try out.appendSlice(a, " xsi:type=\"SOAP-ENC:Struct\">");
            var it = obj.properties.iterator();
            while (it.next()) |entry| try encodeTypedValue(ctx, out, entry.key_ptr.*, entry.value_ptr.*);
            try out.appendSlice(a, "</");
            try out.appendSlice(a, tag);
            try out.appendSlice(a, ">");
        },
        else => {
            try out.appendSlice(a, "/>");
        },
    }
}

fn encodeReturn(ctx: *NativeContext, out: *std.ArrayListUnmanaged(u8), val: Value) RuntimeError!void {
    const a = ctx.allocator;
    switch (val) {
        .null => try out.appendSlice(a, "<return xsi:nil=\"true\"/>"),
        .int => |i| {
            const s = try std.fmt.allocPrint(a, "{d}", .{i});
            defer a.free(s);
            try out.appendSlice(a, "<return xsi:type=\"xsd:int\">");
            try out.appendSlice(a, s);
            try out.appendSlice(a, "</return>");
        },
        .float => |f| {
            const s = try std.fmt.allocPrint(a, "{d}", .{f});
            defer a.free(s);
            try out.appendSlice(a, "<return xsi:type=\"xsd:float\">");
            try out.appendSlice(a, s);
            try out.appendSlice(a, "</return>");
        },
        .bool => |b| {
            try out.appendSlice(a, "<return xsi:type=\"xsd:boolean\">");
            try out.appendSlice(a, if (b) "true" else "false");
            try out.appendSlice(a, "</return>");
        },
        .string => |s| {
            const esc = try xmlEscape(a, s.bytes());
            defer a.free(esc);
            try out.appendSlice(a, "<return xsi:type=\"xsd:string\">");
            try out.appendSlice(a, esc);
            try out.appendSlice(a, "</return>");
        },
        .array, .object => try encodeTypedValue(ctx, out, "return", val),
        else => try out.appendSlice(a, "<return/>"),
    }
}

fn dispatchSoap(ctx: *NativeContext, server: *PhpObject, method: []const u8, args: []const Value) RuntimeError!Value {
    const o = server.get("__object");
    if (o == .object) return ctx.callMethod(o.object, method, args);
    const cls = server.get("__class");
    if (cls == .string) {
        const inst = try ctx.createObject(cls.string.bytes());
        if (ctx.vm.hasMethod(cls.string.bytes(), "__construct")) {
            _ = try ctx.callMethod(inst, "__construct", &.{});
        }
        return ctx.callMethod(inst, method, args);
    }
    // addFunction mode: dispatch to a registered free function by name
    const fns = server.get("__functions");
    if (fns == .array) {
        for (fns.array.entries.items) |e| {
            if (e.value == .string and std.mem.eql(u8, e.value.string.bytes(), method)) {
                return ctx.callFunction(method, args);
            }
        }
    }
    return .null;
}

fn soapServerHandle(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    // request XML: explicit arg, else the raw HTTP body (php://input)
    var req: []const u8 = "";
    if (args.len > 0 and args[0] == .string) {
        req = args[0].string.bytes();
    } else if (ctx.vm.request_vars.get("__raw_body")) |body_val| {
        if (body_val == .string) req = body_val.string.bytes();
    }
    if (req.len == 0) return NativeResult.scalar(.null);

    // locate the SOAP Body open tag's end ("...Body>"); the close tag
    // "</...Body>" appears later, so the first match is the open
    const body_open = std.mem.indexOf(u8, req, "Body>") orelse return NativeResult.scalar(.null);
    var p = body_open + "Body>".len;
    while (p < req.len and (req[p] == ' ' or req[p] == '\n' or req[p] == '\r' or req[p] == '\t')) : (p += 1) {}
    if (p >= req.len or req[p] != '<') return NativeResult.scalar(.null);

    // method element start tag (full name keeps the ns prefix for the close)
    const mtag_start = p + 1;
    var q = mtag_start;
    while (q < req.len and req[q] != '>' and req[q] != ' ' and req[q] != '/') : (q += 1) {}
    const mtag_full = req[mtag_start..q];
    const method = if (std.mem.lastIndexOfScalar(u8, mtag_full, ':')) |ci| mtag_full[ci + 1 ..] else mtag_full;
    var st_end = q;
    while (st_end < req.len and req[st_end] != '>') : (st_end += 1) {}
    const self_closing = st_end > 0 and req[st_end - 1] == '/';

    var arg_vals = std.ArrayListUnmanaged(Value){};
    defer arg_vals.deinit(ctx.allocator);
    if (!self_closing and st_end < req.len) {
        const content_start = st_end + 1;
        var close_marker = std.ArrayListUnmanaged(u8){};
        defer close_marker.deinit(ctx.allocator);
        try close_marker.appendSlice(ctx.allocator, "</");
        try close_marker.appendSlice(ctx.allocator, mtag_full);
        const content_end = std.mem.indexOfPos(u8, req, content_start, close_marker.items) orelse req.len;
        const content = req[content_start..content_end];
        var cp: usize = 0;
        while (cp < content.len) {
            while (cp < content.len and content[cp] != '<') : (cp += 1) {}
            if (cp >= content.len) break;
            var ce = cp + 1;
            while (ce < content.len and content[ce] != '>' and content[ce] != ' ' and content[ce] != '/') : (ce += 1) {}
            var cse = ce;
            while (cse < content.len and content[cse] != '>') : (cse += 1) {}
            if (cse > 0 and content[cse - 1] == '/') {
                try arg_vals.append(ctx.allocator, .{ .string = Value.String.borrowed("") });
                cp = cse + 1;
                continue;
            }
            const txt_start = cse + 1;
            const txt_end = std.mem.indexOfPos(u8, content, txt_start, "</") orelse content.len;
            const txt = try xmlUnescape(ctx.allocator, content[txt_start..txt_end]);
            try ctx.vm.strings.append(ctx.allocator, txt);
            try arg_vals.append(ctx.allocator, .{ .string = Value.String.borrowed(txt) });
            cp = (std.mem.indexOfPos(u8, content, txt_end, ">") orelse content.len -| 1) + 1;
        }
    }

    const result = try dispatchSoap(ctx, obj, method, arg_vals.items);

    const uri_v = obj.get("__uri");
    const uri = if (uri_v == .string) uri_v.string.bytes() else "";
    const uri_esc = try xmlEscape(ctx.allocator, uri);
    defer ctx.allocator.free(uri_esc);
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(ctx.allocator);
    try out.appendSlice(ctx.allocator, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:ns1=\"");
    try out.appendSlice(ctx.allocator, uri_esc);
    // namespace declaration order mirrors PHP's libxml: a nil return references
    // only xsi (xsi:nil), so xsi is declared before xsd; a typed return puts
    // xsd first. matching this exactly keeps the response byte-identical
    const xsd = "xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"";
    const xsi = "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"";
    try out.appendSlice(ctx.allocator, "\" ");
    if (result == .null or (result == .array and !isList(result.array))) {
        try out.appendSlice(ctx.allocator, xsi);
        try out.appendSlice(ctx.allocator, " ");
        try out.appendSlice(ctx.allocator, xsd);
    } else {
        try out.appendSlice(ctx.allocator, xsd);
        if (result == .array and isList(result.array)) try out.appendSlice(ctx.allocator, " xmlns:SOAP-ENC=\"http://schemas.xmlsoap.org/soap/encoding/\"");
        try out.appendSlice(ctx.allocator, " ");
        try out.appendSlice(ctx.allocator, xsi);
    }
    if (result == .array and !isList(result.array)) try out.appendSlice(ctx.allocator, " xmlns:ns2=\"http://xml.apache.org/xml-soap\"");
    if (!(result == .array and isList(result.array))) try out.appendSlice(ctx.allocator, " xmlns:SOAP-ENC=\"http://schemas.xmlsoap.org/soap/encoding/\"");
    try out.appendSlice(ctx.allocator, " SOAP-ENV:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">");
    const response_headers = obj.get("__response_headers");
    if (response_headers == .array and response_headers.array.entries.items.len > 0) {
        try out.appendSlice(ctx.allocator, "<SOAP-ENV:Header>");
        for (response_headers.array.entries.items, 0..) |entry, i| if (entry.value == .object) try appendSoapHeader(ctx, &out, entry.value.object, i);
        try out.appendSlice(ctx.allocator, "</SOAP-ENV:Header>");
        response_headers.array.entries.clearRetainingCapacity();
        response_headers.array.string_index.clearRetainingCapacity();
        response_headers.array.next_int_key = 0;
    }
    try out.appendSlice(ctx.allocator, "<SOAP-ENV:Body><ns1:");
    try out.appendSlice(ctx.allocator, method);
    try out.appendSlice(ctx.allocator, "Response>");
    try encodeReturn(ctx, &out, result);
    try out.appendSlice(ctx.allocator, "</ns1:");
    try out.appendSlice(ctx.allocator, method);
    try out.appendSlice(ctx.allocator, "Response></SOAP-ENV:Body></SOAP-ENV:Envelope>\n");
    try ctx.vm.output.appendSlice(ctx.allocator, out.items);
    return NativeResult.scalar(.null);
}
fn soapServerFault(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}
fn soapServerAddSoapHeader(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const headers = obj.get("__response_headers");
    if (headers != .array) return NativeResult.scalar(.{ .bool = false });
    try headers.array.set(ctx.allocator, .{ .int = headers.array.next_int_key }, args[0]);
    return NativeResult.scalar(.{ .bool = true });
}
fn soapServerGetFunctions(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__functions"));
}
fn soapServerSetPersistence(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn soapHeaderConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len > 0) try obj.set(ctx.allocator, "namespace", args[0]);
    if (args.len > 1) try obj.set(ctx.allocator, "name", args[1]);
    if (args.len > 2) try obj.set(ctx.allocator, "data", args[2]);
    if (args.len > 3) try obj.set(ctx.allocator, "mustUnderstand", args[3]);
    if (args.len > 4) try obj.set(ctx.allocator, "actor", args[4]);
    return NativeResult.scalar(.null);
}

fn soapVarConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len > 0) try obj.set(ctx.allocator, "enc_value", args[0]);
    if (args.len > 1) try obj.set(ctx.allocator, "enc_type", args[1]);
    if (args.len > 2) try obj.set(ctx.allocator, "enc_stype", args[2]);
    if (args.len > 3) try obj.set(ctx.allocator, "enc_ns", args[3]);
    if (args.len > 4) try obj.set(ctx.allocator, "enc_name", args[4]);
    return NativeResult.scalar(.null);
}

fn soapParamConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len > 0) try obj.set(ctx.allocator, "param_data", args[0]);
    if (args.len > 1) try obj.set(ctx.allocator, "param_name", args[1]);
    return NativeResult.scalar(.null);
}

fn soapFaultConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len > 0) try obj.set(ctx.allocator, "faultcode", args[0]);
    if (args.len > 1) {
        try obj.set(ctx.allocator, "faultstring", args[1]);
        try obj.set(ctx.allocator, "message", args[1]); // Exception's message
    }
    if (args.len > 2) try obj.set(ctx.allocator, "faultactor", args[2]);
    if (args.len > 3) try obj.set(ctx.allocator, "detail", args[3]);
    if (args.len > 4) try obj.set(ctx.allocator, "faultname", args[4]);
    return NativeResult.scalar(.null);
}

fn soapFaultToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    const code = obj.get("faultcode");
    const str = obj.get("faultstring");
    const code_s = if (code == .string) code.string.bytes() else "Server";
    const str_s = if (str == .string) str.string.bytes() else "SOAP fault";
    const out = try std.fmt.allocPrint(ctx.allocator, "SoapFault: {s} ({s})", .{ str_s, code_s });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

test {}
