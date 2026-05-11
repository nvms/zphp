const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cInclude("curl/curl.h");
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
    return opts.?.get(.{ .string = key });
}

fn soapClientConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;

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

    try obj.set(ctx.allocator, "__last_request", .{ .string = "" });
    try obj.set(ctx.allocator, "__last_response", .{ .string = "" });
    try obj.set(ctx.allocator, "__last_request_headers", .{ .string = "" });
    try obj.set(ctx.allocator, "__last_response_headers", .{ .string = "" });
    try obj.set(ctx.allocator, "__headers", .{ .array = try ctx.createArray() });
    try obj.set(ctx.allocator, "__cookies", .{ .array = try ctx.createArray() });

    if (wsdl != .null and wsdl != .string) {
        // PHP throws SoapFault here. we accept null only for non-WSDL.
    }
    return .null;
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
            const esc = try xmlEscape(ctx.allocator, s);
            defer ctx.allocator.free(esc);
            try out.appendSlice(ctx.allocator, esc);
        },
        .array => |arr| {
            try out.appendSlice(ctx.allocator, ">");
            for (arr.entries.items) |entry| {
                const child_tag = switch (entry.key) {
                    .string => |s| s,
                    .int => "item",
                };
                try appendValue(ctx, out, child_tag, entry.value);
            }
        },
        else => {
            try out.appendSlice(ctx.allocator, ">");
        },
    }
    try out.appendSlice(ctx.allocator, "</");
    try out.appendSlice(ctx.allocator, tag);
    try out.appendSlice(ctx.allocator, ">");
}

fn buildEnvelope(ctx: *NativeContext, method: []const u8, uri: []const u8, args_array: *PhpArray) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(ctx.allocator);
    try out.appendSlice(ctx.allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ns1="
    );
    const uri_esc = try xmlEscape(ctx.allocator, uri);
    defer ctx.allocator.free(uri_esc);
    try out.appendSlice(ctx.allocator, uri_esc);
    try out.appendSlice(ctx.allocator, "\"><SOAP-ENV:Body><ns1:");
    try out.appendSlice(ctx.allocator, method);
    try out.appendSlice(ctx.allocator, ">");
    for (args_array.entries.items, 0..) |entry, i| {
        var tag_buf: [64]u8 = undefined;
        const tag = switch (entry.key) {
            .string => |s| s,
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
fn parseSoapResponse(ctx: *NativeContext, xml: []const u8) RuntimeError!Value {
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
        const owned = try ctx.allocator.dupe(u8, xml);
        try ctx.strings.append(ctx.allocator, owned);
        return .{ .string = owned };
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
        return .{ .bool = false };
    }

    // first element inside Body is the response method; its children are the result fields
    // skip whitespace then find first element
    var p: usize = 0;
    while (p < body.len and std.ascii.isWhitespace(body[p])) p += 1;
    if (p >= body.len or body[p] != '<') {
        const owned = try ctx.allocator.dupe(u8, body);
        try ctx.strings.append(ctx.allocator, owned);
        return .{ .string = owned };
    }
    // skip past response element tag
    const tag_close = std.mem.indexOfScalarPos(u8, body, p, '>') orelse return .null;
    const inner_start = tag_close + 1;
    // find matching close - approximate by looking for </tag>
    var tag_name_end = p + 1;
    while (tag_name_end < tag_close and body[tag_name_end] != ' ' and body[tag_name_end] != '>') tag_name_end += 1;
    const tag_name = body[p + 1 .. tag_name_end];
    var close_buf: [256]u8 = undefined;
    const close_tag = std.fmt.bufPrint(&close_buf, "</{s}>", .{tag_name}) catch return .null;
    const inner_end = std.mem.indexOfPos(u8, body, inner_start, close_tag) orelse return .null;
    const inner = body[inner_start..inner_end];

    // parse first child of inner (the result) - many SOAP responses are <Foo><return>value</return></Foo>
    var rp: usize = 0;
    while (rp < inner.len and std.ascii.isWhitespace(inner[rp])) rp += 1;
    if (rp >= inner.len or inner[rp] != '<') {
        // no children - return inner trimmed text
        var end = inner.len;
        while (end > 0 and std.ascii.isWhitespace(inner[end - 1])) end -= 1;
        const owned = try ctx.allocator.dupe(u8, inner[rp..end]);
        try ctx.strings.append(ctx.allocator, owned);
        return .{ .string = owned };
    }
    const child_close = std.mem.indexOfScalarPos(u8, inner, rp, '>') orelse return .null;
    var child_name_end = rp + 1;
    while (child_name_end < child_close and inner[child_name_end] != ' ' and inner[child_name_end] != '>') child_name_end += 1;
    const child_name = inner[rp + 1 .. child_name_end];
    var ccbuf: [256]u8 = undefined;
    const child_close_tag = std.fmt.bufPrint(&ccbuf, "</{s}>", .{child_name}) catch return .null;
    const child_inner_start = child_close + 1;
    const child_inner_end = std.mem.indexOfPos(u8, inner, child_inner_start, child_close_tag) orelse return .null;
    const text = inner[child_inner_start..child_inner_end];

    // try to coerce numeric
    if (text.len > 0) {
        if (std.fmt.parseInt(i64, text, 10)) |n| return .{ .int = n } else |_| {}
        if (std.fmt.parseFloat(f64, text)) |f| return .{ .float = f } else |_| {}
    }
    const owned = try ctx.allocator.dupe(u8, text);
    try ctx.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn soapClientCall(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 2 or args[0] != .string or args[1] != .array) return .null;
    const method = args[0].string;
    const args_arr = args[1].array;

    const loc_v = obj.get("__location");
    const uri_v = obj.get("__uri");
    if (loc_v != .string or uri_v != .string) {
        try ctx.vm.setPendingException("SoapFault", "SoapClient requires location and uri options for non-WSDL calls");
        return .{ .bool = false };
    }
    const location = loc_v.string;
    const uri = uri_v.string;

    const envelope = buildEnvelope(ctx, method, uri, args_arr) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .null,
    };
    defer ctx.allocator.free(envelope);

    var action_buf: [512]u8 = undefined;
    const action = std.fmt.bufPrint(&action_buf, "{s}#{s}", .{ uri, method }) catch return .null;

    const env_owned = try ctx.allocator.dupe(u8, envelope);
    try ctx.strings.append(ctx.allocator, env_owned);
    try obj.set(ctx.allocator, "__last_request", .{ .string = env_owned });

    const resp = httpPostSoap(ctx.allocator, location, action, envelope) catch {
        try ctx.vm.setPendingException("SoapFault", "SOAP HTTP request failed");
        return .{ .bool = false };
    };
    defer ctx.allocator.free(resp.body);
    defer ctx.allocator.free(resp.headers);

    const resp_owned = try ctx.allocator.dupe(u8, resp.body);
    try ctx.strings.append(ctx.allocator, resp_owned);
    try obj.set(ctx.allocator, "__last_response", .{ .string = resp_owned });
    const rh_owned = try ctx.allocator.dupe(u8, resp.headers);
    try ctx.strings.append(ctx.allocator, rh_owned);
    try obj.set(ctx.allocator, "__last_response_headers", .{ .string = rh_owned });

    return try parseSoapResponse(ctx, resp.body);
}

fn soapClientMagicCall(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // signature: __call($name, $arguments) - delegate to __soapCall
    return try soapClientCall(ctx, args);
}

fn soapClientGetLastRequest(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const o = getThis(ctx) orelse return .null;
    return o.get("__last_request");
}
fn soapClientGetLastResponse(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const o = getThis(ctx) orelse return .null;
    return o.get("__last_response");
}
fn soapClientGetLastRequestHeaders(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const o = getThis(ctx) orelse return .null;
    return o.get("__last_request_headers");
}
fn soapClientGetLastResponseHeaders(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const o = getThis(ctx) orelse return .null;
    return o.get("__last_response_headers");
}
fn soapClientSetLocation(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getThis(ctx) orelse return .null;
    if (args.len < 1) return .null;
    const prev = o.get("__location");
    try o.set(ctx.allocator, "__location", args[0]);
    return prev;
}
fn soapClientSetSoapHeaders(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getThis(ctx) orelse return .{ .bool = false };
    if (args.len < 1) return .{ .bool = false };
    try o.set(ctx.allocator, "__headers", args[0]);
    return .{ .bool = true };
}
fn soapClientGetFunctions(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .array = try ctx.createArray() };
}
fn soapClientGetTypes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .array = try ctx.createArray() };
}
fn soapClientSetCookie(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getThis(ctx) orelse return .null;
    if (args.len < 2) return .null;
    const cookies_v = o.get("__cookies");
    if (cookies_v != .array) return .null;
    if (args[0] == .string) {
        try cookies_v.array.set(ctx.allocator, .{ .string = args[0].string }, args[1]);
    }
    return .null;
}
fn soapClientGetCookies(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const o = getThis(ctx) orelse return .null;
    return o.get("__cookies");
}

// SoapServer stubs - functional outline. real-world server use is rare from PHP scripts
fn soapServerConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const wsdl = if (args.len > 0) args[0] else .null;
    try obj.set(ctx.allocator, "__wsdl", wsdl);
    try obj.set(ctx.allocator, "__functions", .{ .array = try ctx.createArray() });
    try obj.set(ctx.allocator, "__class", .null);
    try obj.set(ctx.allocator, "__object", .null);
    return .null;
}
fn soapServerAddFunction(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    if (args.len < 1) return .{ .bool = false };
    const fns_v = obj.get("__functions");
    if (fns_v != .array) return .{ .bool = false };
    if (args[0] == .string) {
        try fns_v.array.set(ctx.allocator, .{ .int = fns_v.array.next_int_key }, args[0]);
    } else if (args[0] == .array) {
        for (args[0].array.entries.items) |e| {
            try fns_v.array.set(ctx.allocator, .{ .int = fns_v.array.next_int_key }, e.value);
        }
    }
    return .{ .bool = true };
}
fn soapServerSetObject(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    if (args.len < 1) return .{ .bool = false };
    try obj.set(ctx.allocator, "__object", args[0]);
    return .{ .bool = true };
}
fn soapServerSetClass(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    if (args.len < 1) return .{ .bool = false };
    try obj.set(ctx.allocator, "__class", args[0]);
    return .{ .bool = true };
}
fn soapServerHandle(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // full server handling requires dispatching to user code via VM. left for future iteration.
    return .null;
}
fn soapServerFault(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}
fn soapServerAddSoapHeader(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}
fn soapServerGetFunctions(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return obj.get("__functions");
}
fn soapServerSetPersistence(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn soapHeaderConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len > 0) try obj.set(ctx.allocator, "namespace", args[0]);
    if (args.len > 1) try obj.set(ctx.allocator, "name", args[1]);
    if (args.len > 2) try obj.set(ctx.allocator, "data", args[2]);
    if (args.len > 3) try obj.set(ctx.allocator, "mustUnderstand", args[3]);
    if (args.len > 4) try obj.set(ctx.allocator, "actor", args[4]);
    return .null;
}

fn soapVarConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len > 0) try obj.set(ctx.allocator, "enc_value", args[0]);
    if (args.len > 1) try obj.set(ctx.allocator, "enc_type", args[1]);
    if (args.len > 2) try obj.set(ctx.allocator, "enc_stype", args[2]);
    if (args.len > 3) try obj.set(ctx.allocator, "enc_ns", args[3]);
    if (args.len > 4) try obj.set(ctx.allocator, "enc_name", args[4]);
    return .null;
}

fn soapParamConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len > 0) try obj.set(ctx.allocator, "param_data", args[0]);
    if (args.len > 1) try obj.set(ctx.allocator, "param_name", args[1]);
    return .null;
}

fn soapFaultConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len > 0) try obj.set(ctx.allocator, "faultcode", args[0]);
    if (args.len > 1) {
        try obj.set(ctx.allocator, "faultstring", args[1]);
        try obj.set(ctx.allocator, "message", args[1]); // Exception's message
    }
    if (args.len > 2) try obj.set(ctx.allocator, "faultactor", args[2]);
    if (args.len > 3) try obj.set(ctx.allocator, "detail", args[3]);
    if (args.len > 4) try obj.set(ctx.allocator, "faultname", args[4]);
    return .null;
}

fn soapFaultToString(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .string = "" };
    const code = obj.get("faultcode");
    const str = obj.get("faultstring");
    const code_s = if (code == .string) code.string else "Server";
    const str_s = if (str == .string) str.string else "SOAP fault";
    const out = try std.fmt.allocPrint(ctx.allocator, "SoapFault: {s} ({s})", .{ str_s, code_s });
    try ctx.strings.append(ctx.allocator, out);
    return .{ .string = out };
}

test {}
