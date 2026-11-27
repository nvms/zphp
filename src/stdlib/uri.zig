// php 8.6's uri extension (ext/uri: php_uri.c, php_uri_common.c and the
// parser glue in uri_parser_rfc3986.c / uri_parser_whatwg.c) over the ports
// of uriparser (uri_rfc3986.zig) and lexbor's url module (uri_whatwg.zig).
// a Uri\Rfc3986\Uri or Uri\WhatWg\Url keeps its parsed uri as native state
// (NativeHandle kind .uri), as php's php_uri_object does, so it has no
// properties of its own: var_dump goes through __debugInfo
const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const PhpObject = value_mod.PhpObject;
const PhpArray = value_mod.PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const Args = @import("string_ports.zig").Args;
const rfc = @import("uri_rfc3986.zig");
const ww = @import("uri_whatwg.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub const rfc_class = "Uri\\Rfc3986\\Uri";
pub const whatwg_class = "Uri\\WhatWg\\Url";
const rfc_builder_class = "Uri\\Rfc3986\\UriBuilder";
const whatwg_builder_class = "Uri\\WhatWg\\UrlBuilder";
const uri_type_class = "Uri\\Rfc3986\\UriType";
const rfc_host_type_class = "Uri\\Rfc3986\\UriHostType";
const whatwg_host_type_class = "Uri\\WhatWg\\UrlHostType";
const comparison_mode_class = "Uri\\UriComparisonMode";
const percent_mode_class = "Uri\\WhatWg\\UrlPercentEncodingMode";
const exception_class = "Uri\\UriException";
const error_class = "Uri\\UriError";
const invalid_uri_class = "Uri\\InvalidUriException";
const invalid_url_class = "Uri\\WhatWg\\InvalidUrlException";
const validation_error_class = "Uri\\WhatWg\\UrlValidationError";
const validation_error_type_class = "Uri\\WhatWg\\UrlValidationErrorType";

const validation_error_types = [_][]const u8{
    "DomainToAscii",                        "DomainToUnicode",             "DomainInvalidCodePoint", "HostInvalidCodePoint",
    "Ipv4EmptyPart",                        "Ipv4TooManyParts",            "Ipv4NonNumericPart",     "Ipv4NonDecimalPart",
    "Ipv4OutOfRangePart",                   "Ipv6Unclosed",                "Ipv6InvalidCompression", "Ipv6TooManyPieces",
    "Ipv6MultipleCompression",              "Ipv6InvalidCodePoint",        "Ipv6TooFewPieces",       "Ipv4InIpv6TooManyPieces",
    "Ipv4InIpv6InvalidCodePoint",           "Ipv4InIpv6OutOfRangePart",    "Ipv4InIpv6TooFewParts",  "InvalidUrlUnit",
    "SpecialSchemeMissingFollowingSolidus", "MissingSchemeNonRelativeUrl", "InvalidReverseSoldius",  "InvalidCredentials",
    "HostMissing",                          "PortOutOfRange",              "PortInvalid",            "FileInvalidWindowsDriveLetter",
    "FileInvalidWindowsDriveLetterHost",
};

// get_reason_from_error_type's failure flags, by ErrorType
const validation_error_failure = [_]bool{
    true,  false, true,  true,
    false, true,  true,  false,
    true,  true,  true,  true,
    true,  true,  true,  true,
    true,  true,  true,  false,
    false, true,  false, false,
    true,  true,  true,  false,
    false,
};

comptime {
    std.debug.assert(validation_error_types.len == std.enums.values(ww.ErrorType).len);
    std.debug.assert(validation_error_failure.len == validation_error_types.len);
}

const percent_modes = [_][]const u8{ "Username", "Password", "OpaqueHost", "Path", "OpaquePath", "PathSegment", "Query", "SpecialQuery", "FormQuery", "Fragment" };

// ---- native state ------------------------------------------------------------

const RfcState = struct {
    uri: rfc.Uri,
    // the normalized copy php makes on the first normalized read
    // (get_normalized_uri); null with normalized_ready means the raw uri
    // already is normalized
    normalized: ?rfc.Uri = null,
    normalized_ready: bool = false,
};

const Body = union(enum) { rfc: RfcState, whatwg: ww.Url };

const State = struct {
    a: Allocator,
    body: Body,

    fn destroy(self: *State) void {
        switch (self.body) {
            .rfc => |*r| {
                r.uri.deinit(self.a);
                if (r.normalized) |*n| n.deinit(self.a);
            },
            .whatwg => |*u| u.deinit(self.a),
        }
        self.a.destroy(self);
    }
};

fn stateOf(obj: *PhpObject) ?*State {
    return obj.native.get(State, .uri);
}

fn attach(ctx: *NativeContext, obj: *PhpObject, body: Body) RuntimeError!void {
    const s = try ctx.vm.allocator.create(State);
    s.* = .{ .a = ctx.vm.allocator, .body = body };
    obj.native = .{ .kind = .uri, .ptr = @intFromPtr(s) };
}

fn cleanupUri(obj: *PhpObject) bool {
    if (stateOf(obj)) |s| s.destroy();
    obj.native = .{};
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (obj.pooled or obj.native.kind != .uri) continue;
        _ = cleanupUri(obj);
    }
}

// php_uri_object_handler_clone: the uri is copied, never its normalized form
fn cloneUri(vm: *VM, src: *PhpObject, copy: *PhpObject) bool {
    copy.native = .{};
    const s = stateOf(src) orelse return true;
    const body: Body = switch (s.body) {
        .rfc => |*r| .{ .rfc = .{ .uri = r.uri.clone(vm.allocator) catch return false } },
        .whatwg => |*u| .{ .whatwg = u.clone(vm.allocator) catch return false },
    };
    const n = vm.allocator.create(State) catch {
        var b = body;
        switch (b) {
            .rfc => |*r| r.uri.deinit(vm.allocator),
            .whatwg => |*u| u.deinit(vm.allocator),
        }
        return false;
    };
    n.* = .{ .a = vm.allocator, .body = body };
    copy.native = .{ .kind = .uri, .ptr = @intFromPtr(n) };
    return true;
}

fn thisObject(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    return if (v == .object) v.object else null;
}

fn thisRfc(ctx: *NativeContext) ?*RfcState {
    const obj = thisObject(ctx) orelse return null;
    const s = stateOf(obj) orelse return null;
    return switch (s.body) {
        .rfc => |*r| r,
        else => null,
    };
}

fn thisUrl(ctx: *NativeContext) ?*ww.Url {
    const obj = thisObject(ctx) orelse return null;
    const s = stateOf(obj) orelse return null;
    return switch (s.body) {
        .whatwg => |*u| u,
        else => null,
    };
}

// ---- helpers -------------------------------------------------------------------

fn throwPlain(ctx: *NativeContext, class: []const u8, msg: []const u8) RuntimeError {
    try ctx.vm.setPendingException(class, msg);
    return error.RuntimeError;
}

fn throwFmt(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    return throwPlain(ctx, class, msg);
}

fn enumCase(ctx: *NativeContext, class: []const u8, name: []const u8) Value {
    const def = ctx.vm.classes.getPtr(class) orelse return .null;
    const v = def.constants.get(name) orelse return .null;
    return ctx.vm.enumCase(v);
}

fn caseName(v: Value) []const u8 {
    if (v != .object) return "";
    const n = v.object.get("name");
    return if (n == .string) n.string.bytes() else "";
}

fn strResult(ctx: *NativeContext, bytes: []const u8) RuntimeError!NativeResult {
    return NativeResult.copyString(ctx.allocator, bytes);
}

fn optStrResult(ctx: *NativeContext, bytes: ?[]const u8) RuntimeError!NativeResult {
    const b = bytes orelse return NativeResult.scalar(.null);
    return strResult(ctx, b);
}

fn newString(ctx: *NativeContext, bytes: []const u8) RuntimeError!Value {
    return .{ .string = try Value.String.create(ctx.allocator, bytes) };
}

// a property store that takes its own reference; the value's creator
// reference is dropped
fn setOwned(ctx: *NativeContext, obj: *PhpObject, name: []const u8, v: Value) RuntimeError!void {
    try obj.set(ctx.allocator, name, v);
    if (v == .string) v.string.release();
}

// an object made for a result php frees again (a failed with*(), a failed
// parse()): its handle goes back to the free list
fn discardObject(ctx: *NativeContext, obj: *PhpObject) void {
    obj.retain();
    ctx.vm.releaseValue(.{ .object = obj });
}

// ZEND_TRY_ASSIGN_REF_*: only when the by-reference argument was passed
fn assignByRef(ctx: *NativeContext, args: []const Value, index: usize, v: Value) RuntimeError!void {
    if (index >= args.len) return;
    ctx.setCallerVar(index, args.len, v);
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
}

fn emptyArray(ctx: *NativeContext) RuntimeError!Value {
    return .{ .array = try ctx.createArray() };
}

// ---- rfc 3986 ---------------------------------------------------------------------

// get_normalized_uri
fn rfcNormalized(st: *RfcState, a: Allocator) RuntimeError!*const rfc.Uri {
    if (!st.normalized_ready) {
        const mask = rfc.normalizationMaskRequired(&st.uri);
        if (mask != 0) {
            var copy = st.uri.clone(a) catch |e| return mapRfcOom(e);
            rfc.normalize(a, &copy, mask) catch |e| {
                copy.deinit(a);
                return mapRfcOom(e);
            };
            st.normalized = copy;
        }
        st.normalized_ready = true;
    }
    if (st.normalized) |*n| return n;
    return &st.uri;
}

fn mapRfcOom(e: rfc.Error) RuntimeError {
    return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.RuntimeError,
    };
}

const ReadMode = enum { raw, normalized };

fn rfcRead(ctx: *NativeContext, st: *RfcState, mode: ReadMode) RuntimeError!*const rfc.Uri {
    return switch (mode) {
        .raw => &st.uri,
        .normalized => rfcNormalized(st, ctx.vm.allocator),
    };
}

// port_str_to_zend_long_checked
fn portToLong(text: []const u8) i64 {
    var s = text;
    while (s.len > 1 and s[0] == '0') s = s[1..];
    if (s.len > 20) return -1;
    var result: u64 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') break;
        result = std.math.mul(u64, result, 10) catch return -1;
        result = std.math.add(u64, result, c - '0') catch return -1;
    }
    if (result > std.math.maxInt(i64)) return -1;
    return @intCast(result);
}

fn rfcHost(a: Allocator, uri: *const rfc.Uri) RuntimeError!?[]u8 {
    const text = uri.host_text orelse return null;
    if (uri.host_data == .ip6 or uri.host_data == .ip_future) return try std.mem.concat(a, u8, &.{ "[", text, "]" });
    return try a.dupe(u8, text);
}

fn rfcUsername(uri: *const rfc.Uri) ?[]const u8 {
    const info = uri.user_info orelse return null;
    if (std.mem.indexOfScalar(u8, info, ':')) |c| return info[0..c];
    return info;
}

fn rfcPassword(uri: *const rfc.Uri) ?[]const u8 {
    const info = uri.user_info orelse return null;
    if (std.mem.indexOfScalar(u8, info, ':')) |c| return info[c + 1 ..];
    return "";
}

fn rfcPath(a: Allocator, uri: *const rfc.Uri) RuntimeError![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(a);
    if (uri.segments.items.len > 0) {
        if (uri.absolute_path or uri.hasHost()) try out.append(a, '/');
        for (uri.segments.items, 0..) |seg, i| {
            if (i > 0) try out.append(a, '/');
            try out.appendSlice(a, seg);
        }
    } else if (uri.absolute_path) {
        try out.append(a, '/');
    }
    return out.toOwnedSlice(a);
}

const Component = enum { scheme, username, password, host, port, path, query, fragment };

fn rfcComponent(ctx: *NativeContext, uri: *const rfc.Uri, comptime which: Component) RuntimeError!Value {
    return switch (which) {
        .scheme => if (uri.scheme) |s| newString(ctx, s) else .null,
        .username => if (rfcUsername(uri)) |s| newString(ctx, s) else .null,
        .password => if (rfcPassword(uri)) |s| newString(ctx, s) else .null,
        .host => blk: {
            const h = try rfcHost(ctx.allocator, uri) orelse break :blk .null;
            break :blk .{ .string = try Value.String.adopt(ctx.allocator, h) };
        },
        .port => if (uri.port_text) |p| (if (p.len > 0) Value{ .int = portToLong(p) } else .null) else .null,
        .path => .{ .string = try Value.String.adopt(ctx.allocator, try rfcPath(ctx.allocator, uri)) },
        .query => if (uri.query) |s| newString(ctx, s) else .null,
        .fragment => if (uri.fragment) |s| newString(ctx, s) else .null,
    };
}

fn rfcGetter(comptime which: Component, comptime mode: ReadMode) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
            const st = thisRfc(ctx) orelse return NativeResult.scalar(.null);
            const uri = try rfcRead(ctx, st, mode);
            return NativeResult.transfer(try rfcComponent(ctx, uri, which));
        }
    }.call;
}

fn rfcUserInfoGetter(comptime mode: ReadMode) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
            const st = thisRfc(ctx) orelse return NativeResult.scalar(.null);
            const uri = try rfcRead(ctx, st, mode);
            return optStrResult(ctx, uri.user_info);
        }
    }.call;
}

fn rfcGetUriType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const st = thisRfc(ctx) orelse return NativeResult.scalar(.null);
    const uri = &st.uri;
    const name: []const u8 = if (uri.scheme != null)
        "Uri"
    else if (uri.host_text != null)
        "NetworkPathReference"
    else if (uri.absolute_path)
        "AbsolutePathReference"
    else
        "RelativePathReference";
    return NativeResult.borrowed(enumCase(ctx, uri_type_class, name));
}

fn rfcGetHostType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const st = thisRfc(ctx) orelse return NativeResult.scalar(.null);
    const uri = &st.uri;
    if (uri.host_text == null) return NativeResult.scalar(.null);
    const name: []const u8 = switch (uri.host_data) {
        .ip4 => "IpV4",
        .ip6 => "IpV6",
        .ip_future => "IpVFuture",
        .none => "RegisteredName",
    };
    return NativeResult.borrowed(enumCase(ctx, rfc_host_type_class, name));
}

// php_uri_parser_rfc3986_to_string
fn rfcToString(ctx: *NativeContext, st: *RfcState, mode: ReadMode, exclude_fragment: bool) RuntimeError![]u8 {
    const uri = try rfcRead(ctx, st, mode);
    var text = rfc.toString(ctx.allocator, uri) catch |e| return mapRfcOom(e);
    if (exclude_fragment) {
        if (std.mem.lastIndexOfScalar(u8, text, '#')) |pos| {
            const cut = try ctx.allocator.dupe(u8, text[0..pos]);
            ctx.allocator.free(text);
            text = cut;
        }
    }
    return text;
}

// php_uri_parser_rfc3986_parse_ex: the uri (resolved against a base), or
// null with an exception unless silent
fn rfcParse(ctx: *NativeContext, text: []const u8, base: ?*const rfc.Uri, silent: bool) RuntimeError!?rfc.Uri {
    const a = ctx.vm.allocator;
    var uri = rfc.parse(a, text) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Syntax => {
            if (!silent) return throwPlain(ctx, invalid_uri_class, "The specified URI is malformed");
            return null;
        },
        else => {
            if (!silent) return throwPlain(ctx, error_class, "Failed to parse the specified URI");
            return null;
        },
    };
    if (base) |b| {
        const combined = rfc.addBase(a, &uri, b) catch |e| {
            uri.deinit(a);
            switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.AddBaseRelBase => if (!silent) return throwPlain(ctx, invalid_uri_class, "The specified base URI must be absolute"),
                else => if (!silent) return throwPlain(ctx, error_class, "Failed to resolve the specified URI against the base URI"),
            }
            return null;
        };
        uri.deinit(a);
        uri = combined;
    }
    if (uri.port_text) |p| if (p.len > 0 and portToLong(p) == -1) {
        uri.deinit(a);
        if (!silent) return throwPlain(ctx, invalid_uri_class, "The port is out of range");
        return null;
    };
    return uri;
}

fn rfcBaseArg(a: Args, index: usize) RuntimeError!?*const rfc.Uri {
    const obj = try a.objectOrNull(index, "baseUrl", rfc_class) orelse return null;
    const s = stateOf(obj) orelse return null;
    return switch (s.body) {
        .rfc => |*r| &r.uri,
        else => null,
    };
}

fn cannotModifyReadonly(ctx: *NativeContext, obj: *PhpObject) RuntimeError {
    return throwFmt(ctx, "Error", "Cannot modify readonly object of class {s}", .{obj.class_name});
}

fn rfcConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, rfc_class ++ "::__construct", args);
    const text = try a.str(0, "uri");
    const base = try rfcBaseArg(a, 1);
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    if (stateOf(this) != null) return cannotModifyReadonly(ctx, this);
    var uri = try rfcParse(ctx, text, base, false) orelse return error.RuntimeError;
    errdefer uri.deinit(ctx.vm.allocator);
    try attach(ctx, this, .{ .rfc = .{ .uri = uri } });
    return NativeResult.scalar(.null);
}

fn rfcParseStatic(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, rfc_class ++ "::parse", args);
    const text = try a.str(0, "uri");
    const base = try rfcBaseArg(a, 1);
    const obj = try ctx.createObject(rfc_class);
    var uri = (rfcParse(ctx, text, base, true) catch |e| {
        discardObject(ctx, obj);
        return e;
    }) orelse {
        discardObject(ctx, obj);
        return NativeResult.scalar(.null);
    };
    errdefer uri.deinit(ctx.vm.allocator);
    try attach(ctx, obj, .{ .rfc = .{ .uri = uri } });
    return NativeResult.borrowed(.{ .object = obj });
}

fn rfcResolve(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, rfc_class ++ "::resolve", args);
    const text = try a.str(0, "uri");
    const st = thisRfc(ctx) orelse return NativeResult.scalar(.null);
    const obj = try ctx.createObject(rfc_class);
    var uri = (rfcParse(ctx, text, &st.uri, false) catch |e| {
        discardObject(ctx, obj);
        return e;
    }) orelse {
        discardObject(ctx, obj);
        return error.RuntimeError;
    };
    errdefer uri.deinit(ctx.vm.allocator);
    try attach(ctx, obj, .{ .rfc = .{ .uri = uri } });
    return NativeResult.borrowed(.{ .object = obj });
}

// the uriparser setter results php maps to exceptions
fn rfcWriteFailure(ctx: *NativeContext, comptime component: []const u8, e: rfc.Error) RuntimeError {
    return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.Syntax => throwPlain(ctx, invalid_uri_class, "The specified " ++ component ++ " is malformed"),
        error.SetUserInfoHostNotSet => throwPlain(ctx, invalid_uri_class, "Cannot set a userinfo without having a host"),
        error.SetHostPortSet => throwPlain(ctx, invalid_uri_class, "Cannot remove the host from a URI that has a port"),
        error.SetHostUserInfoSet => throwPlain(ctx, invalid_uri_class, "Cannot remove the host from a URI that has a userinfo"),
        error.SetPortHostNotSet => throwPlain(ctx, invalid_uri_class, "Cannot set a port without having a host"),
        else => throwPlain(ctx, error_class, "Failed to update the " ++ component),
    };
}

const RfcValue = union(enum) { null, str: []const u8, long: i64 };

fn rfcWrite(ctx: *NativeContext, uri: *rfc.Uri, comptime which: Component, v: RfcValue) RuntimeError!void {
    const a = ctx.vm.allocator;
    const text: ?[]const u8 = switch (v) {
        .null => null,
        .str => |s| s,
        .long => null,
    };
    switch (which) {
        .scheme => rfc.setScheme(a, uri, text) catch |e| return rfcWriteFailure(ctx, "scheme", e),
        .username => rfc.setUserInfo(a, uri, text) catch |e| return rfcWriteFailure(ctx, "userinfo", e),
        .host => rfc.setHostAuto(a, uri, text) catch |e| return rfcWriteFailure(ctx, "host", e),
        .port => {
            var buf: [24]u8 = undefined;
            const port_text: ?[]const u8 = switch (v) {
                .long => |n| std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable,
                else => null,
            };
            rfc.setPortText(a, uri, port_text) catch |e| return rfcWriteFailure(ctx, "port", e);
        },
        // an empty path is uriparser's NULL range
        .path => rfc.setPath(a, uri, if (text) |t| (if (t.len == 0) null else t) else null) catch |e| return rfcWriteFailure(ctx, "path", e),
        .query => rfc.setQuery(a, uri, text) catch |e| return rfcWriteFailure(ctx, "query", e),
        .fragment => rfc.setFragment(a, uri, text) catch |e| return rfcWriteFailure(ctx, "fragment", e),
        .password => unreachable,
    }
}

const ArgKind = enum { str, str_or_null, long_or_null };

fn writeArg(a: Args, comptime kind: ArgKind, comptime name: []const u8) RuntimeError!RfcValue {
    return switch (kind) {
        .str => .{ .str = try a.str(0, name) },
        .str_or_null => if (try a.strOrNull(0, name)) |s| .{ .str = s } else .null,
        .long_or_null => if (try a.longOrNull(0, name)) |n| .{ .long = n } else .null,
    };
}

// php_uri_property_write_helper: a clone takes the new component
fn rfcWither(comptime method: []const u8, comptime which: Component, comptime kind: ArgKind, comptime name: []const u8) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const v = try writeArg(Args.init(ctx, rfc_class ++ "::" ++ method, args), kind, name);
            const st = thisRfc(ctx) orelse return NativeResult.scalar(.null);
            const obj = try ctx.createObject(rfc_class);
            var uri = st.uri.clone(ctx.vm.allocator) catch |e| {
                discardObject(ctx, obj);
                return mapRfcOom(e);
            };
            rfcWrite(ctx, &uri, which, v) catch |e| {
                uri.deinit(ctx.vm.allocator);
                discardObject(ctx, obj);
                return e;
            };
            attach(ctx, obj, .{ .rfc = .{ .uri = uri } }) catch |e| {
                uri.deinit(ctx.vm.allocator);
                discardObject(ctx, obj);
                return e;
            };
            return NativeResult.borrowed(.{ .object = obj });
        }
    }.call;
}

fn comparisonExcludesFragment(a: Args, index: usize) RuntimeError!bool {
    if (!a.has(index)) return true;
    const mode = try a.object(index, "comparisonMode", comparison_mode_class);
    return !std.mem.eql(u8, caseName(.{ .object = mode }), "IncludeFragment");
}

fn rfcEquals(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, rfc_class ++ "::equals", args);
    const that = try a.object(0, "uri", rfc_class);
    const exclude = try comparisonExcludesFragment(a, 1);
    const st = thisRfc(ctx) orelse return NativeResult.scalar(.null);
    const other = stateOf(that) orelse return NativeResult.scalar(.{ .bool = false });
    if (other.body != .rfc) return NativeResult.scalar(.{ .bool = false });
    const this_str = try rfcToString(ctx, st, .normalized, exclude);
    defer ctx.allocator.free(this_str);
    const that_str = try rfcToString(ctx, &other.body.rfc, .normalized, exclude);
    defer ctx.allocator.free(that_str);
    return NativeResult.scalar(.{ .bool = std.mem.eql(u8, this_str, that_str) });
}

fn rfcToStringMethod(comptime mode: ReadMode) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
            const st = thisRfc(ctx) orelse return NativeResult.literal("");
            const text = try rfcToString(ctx, st, mode, false);
            return NativeResult.takeString(try Value.String.adopt(ctx.allocator, text));
        }
    }.call;
}

// ---- debug info and serialization, both parsers ---------------------------------

fn debugInfo(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    const obj = thisObject(ctx) orelse return NativeResult.borrowed(.{ .array = arr });
    const s = stateOf(obj) orelse return NativeResult.borrowed(.{ .array = arr });
    const names = [_][]const u8{ "scheme", "username", "password", "host", "port", "path", "query", "fragment" };
    inline for (names, 0..) |name, i| {
        const which: Component = @fromBackingInt(@intCast(i));
        const v = switch (s.body) {
            .rfc => |*r| try rfcComponent(ctx, &r.uri, which),
            .whatwg => |*u| try urlComponent(ctx, u, which, .raw),
        };
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, v);
        if (v == .string) v.string.release();
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn serializeUri(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const s = stateOf(obj) orelse return NativeResult.scalar(.null);
    const text = switch (s.body) {
        .rfc => |*r| try rfcToString(ctx, r, .raw, false),
        .whatwg => |*u| try ww.serialize(ctx.allocator, u, false),
    };
    const str = try Value.String.adopt(ctx.allocator, text);
    defer str.release();
    const state = try ctx.createArray();
    try state.set(ctx.allocator, .{ .string = Value.String.borrowed("uri") }, .{ .string = str });
    const result = try ctx.createArray();
    try result.append(ctx.allocator, .{ .array = state });
    try result.append(ctx.allocator, .{ .array = try ctx.createArray() });
    return NativeResult.borrowed(.{ .array = result });
}

fn invalidSerialization(ctx: *NativeContext, obj: *PhpObject) RuntimeError {
    return throwFmt(ctx, "Exception", "Invalid serialization data for {s} object", .{obj.class_name});
}

fn unserializeUri(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const label = if (std.mem.eql(u8, obj.class_name, whatwg_class)) whatwg_class ++ "::__unserialize" else rfc_class ++ "::__unserialize";
    if (args.len < 1 or args[0] != .array) return Args.init(ctx, label, args).typeError(0, "data", "array");
    const data = args[0].array;
    if (stateOf(obj) != null) {
        // php throws two exceptions here on purpose, chained
        if (cannotModifyReadonly(ctx, obj) == error.OutOfMemory) return error.OutOfMemory;
        const first = ctx.vm.takePending();
        defer if (first) |f| ctx.vm.stackRelease(f);
        if (invalidSerialization(ctx, obj) == error.OutOfMemory) return error.OutOfMemory;
        if (first) |f| if (f == .object) if (ctx.vm.pending_exception) |exc| if (exc == .object) {
            _ = try ctx.vm.chainPrevious(exc.object, f.object);
        };
        return error.RuntimeError;
    }
    if (data.entries.items.len != 2) return invalidSerialization(ctx, obj);
    const first = data.get(.{ .int = 0 });
    if (first != .array or first.array.entries.items.len != 1) return invalidSerialization(ctx, obj);
    const uri_zv = first.array.get(.{ .string = Value.String.borrowed("uri") });
    if (uri_zv != .string) return invalidSerialization(ctx, obj);
    const text = uri_zv.string.bytes();
    if (std.mem.eql(u8, obj.class_name, whatwg_class)) {
        var p = ww.Parser.init(ctx.vm.allocator);
        defer p.deinit();
        var url = try ww.parse(&p, null, text) orelse return invalidSerialization(ctx, obj);
        errdefer url.deinit(ctx.vm.allocator);
        try attach(ctx, obj, .{ .whatwg = url });
    } else {
        var uri = try rfcParse(ctx, text, null, true) orelse return invalidSerialization(ctx, obj);
        errdefer uri.deinit(ctx.vm.allocator);
        try attach(ctx, obj, .{ .rfc = .{ .uri = uri } });
    }
    const second = data.get(.{ .int = 1 });
    if (second != .array or second.array.entries.items.len > 0) return invalidSerialization(ctx, obj);
    return NativeResult.scalar(.null);
}

// ---- whatwg ------------------------------------------------------------------------

fn validationError(ctx: *NativeContext, t: ww.ErrorType, context: []const u8) RuntimeError!*PhpObject {
    const obj = try ctx.createObject(validation_error_class);
    try setOwned(ctx, obj, "context", try newString(ctx, context));
    try obj.set(ctx.allocator, "type", enumCase(ctx, validation_error_type_class, validation_error_types[@backingInt(t)]));
    try obj.set(ctx.allocator, "failure", .{ .bool = validation_error_failure[@backingInt(t)] });
    return obj;
}

// fill_errors_inner: the log as UrlValidationError objects, appended to arr;
// the first failure's type is the exception's reason. the log is emptied
fn appendLog(ctx: *NativeContext, p: *ww.Parser, arr: *PhpArray) RuntimeError!?[]const u8 {
    var reason: ?[]const u8 = null;
    for (p.log.items) |entry| {
        const err = try validationError(ctx, entry.type, entry.context);
        try arr.append(ctx.allocator, .{ .object = err });
        if (validation_error_failure[@backingInt(entry.type)] and reason == null) reason = validation_error_types[@backingInt(entry.type)];
    }
    p.clean();
    return reason;
}

fn throwInvalidUrl(ctx: *NativeContext, comptime component: []const u8, reason: ?[]const u8, errors: *PhpArray) RuntimeError {
    if (reason) |r| {
        const msg = try std.fmt.allocPrint(ctx.allocator, "The specified " ++ component ++ " is malformed ({s})", .{r});
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException(invalid_url_class, msg);
    } else {
        try ctx.vm.setPendingException(invalid_url_class, "The specified " ++ component ++ " is malformed");
    }
    if (ctx.vm.pending_exception) |exc| if (exc == .object) try exc.object.set(ctx.allocator, "errors", .{ .array = errors });
    return error.RuntimeError;
}

// throw_invalid_url_exception_during_write
fn throwDuringWrite(ctx: *NativeContext, p: *ww.Parser, comptime component: []const u8) RuntimeError {
    const errors = try ctx.createArray();
    const reason = try appendLog(ctx, p, errors);
    return throwInvalidUrl(ctx, component, reason, errors);
}

// php_uri_parser_whatwg_throw_exception: no errors
fn throwUrlMessage(ctx: *NativeContext, msg: []const u8) RuntimeError {
    try ctx.vm.setPendingException(invalid_url_class, msg);
    if (ctx.vm.pending_exception) |exc| if (exc == .object) try exc.object.set(ctx.allocator, "errors", try emptyArray(ctx));
    return error.RuntimeError;
}

// php_uri_parser_whatwg_component_error: one error with an empty context
fn componentError(ctx: *NativeContext, comptime component: []const u8, t: ?ww.ErrorType) RuntimeError {
    const errors = try ctx.createArray();
    var reason: ?[]const u8 = null;
    if (t) |et| {
        try errors.append(ctx.allocator, .{ .object = try validationError(ctx, et, "") });
        reason = validation_error_types[@backingInt(et)];
    }
    return throwInvalidUrl(ctx, component, reason, errors);
}

fn urlHost(ctx: *NativeContext, url: *const ww.Url, mode: UrlReadMode) RuntimeError!Value {
    const a = ctx.allocator;
    return switch (url.host.type) {
        .ipv4 => .{ .string = try Value.String.adopt(a, try ww.serializeHostIpv4(a, url.host.ipv4)) },
        .ipv6 => blk: {
            const inner = try ww.serializeHostIpv6(a, url.host.ipv6);
            defer a.free(inner);
            break :blk .{ .string = try Value.String.adopt(a, try std.mem.concat(a, u8, &.{ "[", inner, "]" })) };
        },
        .empty => newString(ctx, ""),
        .undef => .null,
        .domain, .@"opaque" => switch (mode) {
            .unicode => .{ .string = try Value.String.adopt(a, try ww.serializeHostUnicode(a, &url.host)) },
            else => newString(ctx, url.host.str),
        },
    };
}

const UrlReadMode = enum { raw, ascii, unicode };

// includes_credentials
fn urlHasCredentials(url: *const ww.Url) bool {
    return url.username.len > 0 or url.password.len > 0;
}

fn urlComponent(ctx: *NativeContext, url: *const ww.Url, which: Component, mode: UrlReadMode) RuntimeError!Value {
    return switch (which) {
        .scheme => newString(ctx, url.scheme_name),
        .username => if (urlHasCredentials(url)) newString(ctx, url.username) else .null,
        .password => if (urlHasCredentials(url)) newString(ctx, url.password) else .null,
        .host => urlHost(ctx, url, mode),
        .port => if (url.has_port) .{ .int = url.port } else .null,
        .path => newString(ctx, url.path_str),
        .query => if (url.query) |q| newString(ctx, q) else .null,
        .fragment => if (url.fragment) |f| newString(ctx, f) else .null,
    };
}

fn urlGetter(comptime which: Component, comptime mode: UrlReadMode) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
            const url = thisUrl(ctx) orelse return NativeResult.scalar(.null);
            return NativeResult.transfer(try urlComponent(ctx, url, which, mode));
        }
    }.call;
}

fn urlGetHostType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const url = thisUrl(ctx) orelse return NativeResult.scalar(.null);
    const name: []const u8 = switch (url.host.type) {
        .ipv4 => "IpV4",
        .ipv6 => "IpV6",
        .domain => "Domain",
        .empty => "Empty",
        .@"opaque" => "Opaque",
        .undef => return NativeResult.scalar(.null),
    };
    return NativeResult.borrowed(enumCase(ctx, whatwg_host_type_class, name));
}

fn urlIsSpecialScheme(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const url = thisUrl(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = ww.isSpecial(url) });
}

// php_uri_parser_whatwg_parse_ex plus php_uri_instantiate_uri's handling of
// the errors argument: the url, or null with the exception thrown unless
// silent. errors_out receives the errors array when the caller passed one
fn urlParse(ctx: *NativeContext, text: []const u8, base: ?*const ww.Url, silent: bool, want_errors: bool, errors_out: *?*PhpArray) RuntimeError!?ww.Url {
    var p = ww.Parser.init(ctx.vm.allocator);
    defer p.deinit();
    const url = try ww.parse(&p, base, text);
    if ((url == null and !silent) or want_errors) {
        const errors = try ctx.createArray();
        const reason = appendLog(ctx, &p, errors) catch |e| {
            if (url) |u| {
                var m = u;
                m.deinit(ctx.vm.allocator);
            }
            return e;
        };
        if (url == null and !silent) {
            if (want_errors) {
                errors.retain();
                errors_out.* = errors;
            }
            return throwInvalidUrl(ctx, "URI", reason, errors);
        }
        errors_out.* = errors;
    }
    return url;
}

fn urlBaseArg(a: Args, index: usize) RuntimeError!?*const ww.Url {
    const obj = try a.objectOrNull(index, "baseUrl", whatwg_class) orelse return null;
    const s = stateOf(obj) orelse return null;
    return switch (s.body) {
        .whatwg => |*u| u,
        else => null,
    };
}

// php_uri_instantiate_uri for the whatwg parser: `target` is the object to
// fill (the constructor's $this) or null to make one
fn urlInstantiate(ctx: *NativeContext, args: []const Value, text: []const u8, base: ?*const ww.Url, should_throw: bool, target: ?*PhpObject, errors_index: usize) RuntimeError!NativeResult {
    const want_errors = args.len > errors_index;
    const obj = target orelse try ctx.createObject(whatwg_class);
    var errors: ?*PhpArray = null;
    const parsed = urlParse(ctx, text, base, !should_throw, want_errors, &errors) catch |e| {
        if (e == error.RuntimeError and should_throw and want_errors) {
            // php hands an empty array back when it throws
            if (errors) |arr| ctx.vm.releaseValue(.{ .array = arr });
            const exc = ctx.vm.takePending();
            defer if (exc) |x| ctx.vm.setPendingOwned(x);
            ctx.setCallerVar(errors_index, args.len, try emptyArray(ctx));
        }
        if (target == null) discardObject(ctx, obj);
        return e;
    };
    if (parsed == null) {
        if (errors) |arr| assignByRef(ctx, args, errors_index, .{ .array = arr }) catch |e| {
            if (target == null) discardObject(ctx, obj);
            return e;
        };
        if (target == null) discardObject(ctx, obj);
        return NativeResult.scalar(.null);
    }
    var url = parsed.?;
    if (errors) |arr| assignByRef(ctx, args, errors_index, .{ .array = arr }) catch |e| {
        url.deinit(ctx.vm.allocator);
        if (target == null) discardObject(ctx, obj);
        return e;
    };
    attach(ctx, obj, .{ .whatwg = url }) catch |e| {
        url.deinit(ctx.vm.allocator);
        if (target == null) discardObject(ctx, obj);
        return e;
    };
    if (target != null) return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = obj });
}

fn urlConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, whatwg_class ++ "::__construct", args);
    const text = try a.str(0, "uri");
    const base = try urlBaseArg(a, 1);
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    if (stateOf(this) != null) return cannotModifyReadonly(ctx, this);
    return urlInstantiate(ctx, args, text, base, true, this, 2);
}

fn urlParseStatic(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, whatwg_class ++ "::parse", args);
    const text = try a.str(0, "uri");
    const base = try urlBaseArg(a, 1);
    return urlInstantiate(ctx, args, text, base, false, null, 2);
}

fn urlResolve(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, whatwg_class ++ "::resolve", args);
    const text = try a.str(0, "uri");
    const url = thisUrl(ctx) orelse return NativeResult.scalar(.null);
    return urlInstantiate(ctx, args, text, url, true, null, 1);
}

// zval_string_or_null_to_lexbor_str / zval_long_or_null_to_lexbor_str
fn urlWriteText(buf: []u8, v: RfcValue) []const u8 {
    return switch (v) {
        .null => "",
        .str => |s| s,
        .long => |n| std.fmt.bufPrint(buf, "{d}", .{n}) catch unreachable,
    };
}

// the property handlers' write: false with the exception thrown
fn urlWrite(ctx: *NativeContext, p: *ww.Parser, url: *ww.Url, comptime which: Component, v: RfcValue) RuntimeError!void {
    var buf: [24]u8 = undefined;
    const text = urlWriteText(&buf, v);
    p.clean();
    const a = ctx.vm.allocator;
    const ok = switch (which) {
        .scheme => try ww.protocolSet(p, url, text),
        .username => try ww.usernameSet(a, url, text),
        .password => try ww.passwordSet(a, url, text),
        .host => try ww.hostnameSet(p, url, text),
        .port => try ww.portSet(p, url, text),
        .path => try ww.pathnameSet(p, url, text),
        .query => try ww.searchSet(p, url, text),
        .fragment => try ww.hashSet(p, url, text),
    };
    if (!ok) return throwDuringWrite(ctx, p, switch (which) {
        .query => "query string",
        else => @tagName(which),
    });
}

fn urlWither(comptime method: []const u8, comptime which: Component, comptime kind: ArgKind, comptime name: []const u8) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const v = try writeArg(Args.init(ctx, whatwg_class ++ "::" ++ method, args), kind, name);
            const url = thisUrl(ctx) orelse return NativeResult.scalar(.null);
            const obj = try ctx.createObject(whatwg_class);
            var copy = url.clone(ctx.vm.allocator) catch |e| {
                discardObject(ctx, obj);
                return e;
            };
            var p = ww.Parser.init(ctx.vm.allocator);
            defer p.deinit();
            urlWrite(ctx, &p, &copy, which, v) catch |e| {
                copy.deinit(ctx.vm.allocator);
                discardObject(ctx, obj);
                return e;
            };
            attach(ctx, obj, .{ .whatwg = copy }) catch |e| {
                copy.deinit(ctx.vm.allocator);
                discardObject(ctx, obj);
                return e;
            };
            return NativeResult.borrowed(.{ .object = obj });
        }
    }.call;
}

fn urlEquals(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, whatwg_class ++ "::equals", args);
    const that = try a.object(0, "url", whatwg_class);
    const exclude = try comparisonExcludesFragment(a, 1);
    const url = thisUrl(ctx) orelse return NativeResult.scalar(.null);
    const other = stateOf(that) orelse return NativeResult.scalar(.{ .bool = false });
    if (other.body != .whatwg) return NativeResult.scalar(.{ .bool = false });
    const this_str = try ww.serialize(ctx.allocator, url, exclude);
    defer ctx.allocator.free(this_str);
    const that_str = try ww.serialize(ctx.allocator, &other.body.whatwg, exclude);
    defer ctx.allocator.free(that_str);
    return NativeResult.scalar(.{ .bool = std.mem.eql(u8, this_str, that_str) });
}

fn urlToAsciiString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const url = thisUrl(ctx) orelse return NativeResult.literal("");
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try ww.serialize(ctx.allocator, url, false)));
}

fn urlToUnicodeString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const url = thisUrl(ctx) orelse return NativeResult.literal("");
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try ww.serializeIdna(ctx.allocator, url, false)));
}

// Uri\WhatWg\url_percent_encode
fn native_url_percent_encode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, "Uri\\WhatWg\\url_percent_encode", args);
    const input = try a.str(0, "input");
    const mode_obj = try a.object(1, "mode", percent_mode_class);
    const mode_name = caseName(.{ .object = mode_obj });
    var map = ww.percentEncodingMap();
    // % is percent-encoded
    map['%'] = 0xff;
    var mask: u8 = ww.Map.fragment;
    var space_as_plus = false;
    if (std.mem.eql(u8, mode_name, "Username") or std.mem.eql(u8, mode_name, "Password")) {
        mask = ww.Map.userinfo;
    } else if (std.mem.eql(u8, mode_name, "OpaqueHost") or std.mem.eql(u8, mode_name, "OpaquePath")) {
        mask = ww.Map.c0;
    } else if (std.mem.eql(u8, mode_name, "Path")) {
        mask = ww.Map.path;
    } else if (std.mem.eql(u8, mode_name, "PathSegment")) {
        mask = ww.Map.path;
        map['/'] |= ww.Map.path;
    } else if (std.mem.eql(u8, mode_name, "Query")) {
        mask = ww.Map.query;
    } else if (std.mem.eql(u8, mode_name, "SpecialQuery")) {
        mask = ww.Map.special_query;
    } else if (std.mem.eql(u8, mode_name, "FormQuery")) {
        mask = ww.Map.x_www_form;
        space_as_plus = true;
    }
    const out = try ww.percentEncodeUtf8(ctx.allocator, input, &map, mask, space_as_plus);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, out));
}

pub const entries = .{
    .{ "Uri\\WhatWg\\url_percent_encode", native_url_percent_encode },
};

// ---- exceptions and validation errors ------------------------------------------------

// is_list_of_whatwg_validation_errors: references don't count
fn isValidationErrorList(vm: *VM, arr: *PhpArray) bool {
    for (arr.entries.items, 0..) |entry, i| {
        if (entry.key != .int or entry.key.int != @as(i64, @intCast(i))) return false;
        if (entry.ref != null) return false;
        if (entry.value != .object or !vm.isInstanceOf(entry.value.object.class_name, validation_error_class)) return false;
    }
    return true;
}

fn invalidUrlExceptionConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const a = Args.init(ctx, invalid_url_class ++ "::__construct", args);
    const message = if (a.has(0)) try a.str(0, "message") else null;
    var errors: ?*PhpArray = null;
    if (a.has(1)) {
        if (args[1] != .array) return a.typeError(1, "errors", "array");
        errors = args[1].array;
    }
    const code = if (a.has(2)) try a.long(2, "code") else 0;
    const previous = if (a.has(3)) try a.objectOrNull(3, "previous", "Throwable") else null;
    // zend_update_exception_properties
    if (message) |m| {
        if (args[0] == .string) try this.set(ctx.allocator, "message", args[0]) else try setOwned(ctx, this, "message", try newString(ctx, m));
    }
    if (code != 0) try this.set(ctx.allocator, "code", .{ .int = code });
    if (previous) |p| try this.set(ctx.allocator, "previous", .{ .object = p });
    if (errors) |arr| if (!isValidationErrorList(ctx.vm, arr)) return a.valueError(1, "errors", "must be a list of " ++ validation_error_class);
    // zend_update_property on the readonly property a first call set
    if (this.rawForScope("errors", invalid_url_class) != .undef) return throwPlain(ctx, "Error", "Cannot modify readonly property " ++ invalid_url_class ++ "::$errors");
    if (errors) |arr| {
        try this.setForScope(ctx.allocator, "errors", .{ .array = arr }, invalid_url_class);
    } else {
        try this.setForScope(ctx.allocator, "errors", try emptyArray(ctx), invalid_url_class);
    }
    return NativeResult.scalar(.null);
}

fn validationErrorConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const a = Args.init(ctx, validation_error_class ++ "::__construct", args);
    const context = try a.str(0, "context");
    const t = try a.object(1, "type", validation_error_type_class);
    const failure = try a.boolean(2, "failure", false);
    for ([_][]const u8{ "context", "type", "failure" }) |name| {
        if (this.rawForScope(name, validation_error_class) != .undef) return throwFmt(ctx, "Error", "Cannot modify readonly property " ++ validation_error_class ++ "::${s}", .{name});
    }
    if (args[0] == .string) try this.set(ctx.allocator, "context", args[0]) else try setOwned(ctx, this, "context", try newString(ctx, context));
    try this.set(ctx.allocator, "type", .{ .object = t });
    try this.set(ctx.allocator, "failure", .{ .bool = failure });
    return NativeResult.scalar(.null);
}

// ---- the builders --------------------------------------------------------------------

fn builderProp(obj: *PhpObject, class: []const u8, name: []const u8) Value {
    return obj.getForScope(name, class);
}

fn builderReset(comptime class: []const u8, comptime empty_strings: []const []const u8, comptime names: []const []const u8) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
            const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
            inline for (names) |name| {
                const is_empty_string = comptime blk: {
                    for (empty_strings) |e| if (std.mem.eql(u8, e, name)) break :blk true;
                    break :blk false;
                };
                const v: Value = if (is_empty_string) .{ .string = Value.String.borrowed("") } else .null;
                try this.setForScope(ctx.allocator, name, v, class);
            }
            return NativeResult.borrowed(.{ .object = this });
        }
    }.call;
}

const Validator = enum { none, rfc_scheme, rfc_userinfo, rfc_host, rfc_port, rfc_path, rfc_query, rfc_fragment, ww_scheme, ww_host, ww_port };

fn validateRfc(ctx: *NativeContext, comptime component: []const u8, ok: bool) RuntimeError!void {
    if (!ok) return throwPlain(ctx, invalid_uri_class, "The specified " ++ component ++ " is malformed");
}

// php_uri_parser_rfc3986_host_validate
fn rfcHostWellFormed(p: []const u8) bool {
    if (p.len == 0) return true;
    if (p[0] == '[') {
        if (p[p.len - 1] != ']') return false;
        if (p.len >= 2 and (p[1] == 'v' or p[1] == 'V')) return rfc.isWellFormedHostIpFuture(p[1 .. p.len - 1]);
        if (p.len < 2) return false;
        return rfc.isWellFormedHostIp6(p[1 .. p.len - 1]);
    }
    if (rfc.isWellFormedHostIp4(p)) return true;
    return rfc.isWellFormedHostRegName(p);
}

fn isTabOrNewline(c: u8) bool {
    return c == '\t' or c == '\n' or c == '\r';
}

// php_uri_parser_whatwg_scheme_validate
fn wwSchemeValidate(ctx: *NativeContext, s: []const u8) RuntimeError!void {
    var seen_first = false;
    for (s) |c| {
        if (isTabOrNewline(c)) continue;
        if (!seen_first) {
            if (!std.ascii.isAlphabetic(c)) return componentError(ctx, "scheme", .missing_scheme_non_relative_url);
            seen_first = true;
        } else if (!std.ascii.isAlphanumeric(c) and c != '+' and c != '-' and c != '.') {
            return componentError(ctx, "scheme", .missing_scheme_non_relative_url);
        }
    }
    if (!seen_first) return componentError(ctx, "scheme", .missing_scheme_non_relative_url);
}

// php_uri_parser_whatwg_host_validate
fn wwHostValidate(ctx: *NativeContext, host: []const u8) RuntimeError!void {
    if (host.len == 0) return;
    var first: usize = 0;
    while (first < host.len and isTabOrNewline(host[first])) first += 1;
    for (host[first..]) |c| {
        if (c == '/' or c == '?' or c == '#' or c == '\\') return componentError(ctx, "host", .host_invalid_code_point);
    }
    // *first is the string's nul terminator when only tabs were given
    if (first >= host.len or host[first] != '[') return;
    var stripped: std.ArrayListUnmanaged(u8) = .empty;
    defer stripped.deinit(ctx.allocator);
    for (host[first..]) |c| if (!isTabOrNewline(c)) try stripped.append(ctx.allocator, c);
    var p = ww.Parser.init(ctx.vm.allocator);
    defer p.deinit();
    var ipv6: [8]u16 = undefined;
    if (!try ww.parseHostIpv6(&p, stripped.items, &ipv6)) {
        if (p.log.items.len > 0) return componentError(ctx, "host", p.log.items[p.log.items.len - 1].type);
        return componentError(ctx, "host", null);
    }
}

fn builderSetter(comptime class: []const u8, comptime method: []const u8, comptime prop: []const u8, comptime kind: ArgKind, comptime param: []const u8, comptime validator: Validator) fn (*NativeContext, []const Value) RuntimeError!NativeResult {
    return struct {
        fn call(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
            const a = Args.init(ctx, class ++ "::" ++ method, args);
            const v = try writeArg(a, kind, param);
            const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
            switch (v) {
                .null => {},
                .str => |s| switch (validator) {
                    .rfc_scheme => try validateRfc(ctx, "scheme", rfc.isWellFormedScheme(s)),
                    .rfc_userinfo => try validateRfc(ctx, "userinfo", rfc.isWellFormedUserInfo(s)),
                    .rfc_host => try validateRfc(ctx, "host", rfcHostWellFormed(s)),
                    // the build checks a leading "/" when there's a host
                    .rfc_path => try validateRfc(ctx, "path", rfc.isWellFormedPath(s, false)),
                    .rfc_query => try validateRfc(ctx, "query", rfc.isWellFormedQuery(s)),
                    .rfc_fragment => try validateRfc(ctx, "fragment", rfc.isWellFormedFragment(s)),
                    .ww_scheme => try wwSchemeValidate(ctx, s),
                    .ww_host => try wwHostValidate(ctx, s),
                    else => {},
                },
                .long => |n| switch (validator) {
                    .rfc_port => {
                        var buf: [24]u8 = undefined;
                        try validateRfc(ctx, "port", rfc.isWellFormedPort(std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable));
                    },
                    .ww_port => {
                        if (n < 0) return componentError(ctx, "port", .port_invalid);
                        if (n > 65535) return componentError(ctx, "port", .port_out_of_range);
                    },
                    else => {},
                },
            }
            const stored: Value = switch (v) {
                .null => .null,
                .str => if (args[0] == .string) args[0] else try newString(ctx, v.str),
                .long => |n| .{ .int = n },
            };
            try this.setForScope(ctx.allocator, prop, stored, class);
            if (stored == .string and args[0] != .string) stored.string.release();
            return NativeResult.borrowed(.{ .object = this });
        }
    }.call;
}

fn propValue(v: Value) RfcValue {
    return switch (v) {
        .string => |s| .{ .str = s.bytes() },
        .int => |n| .{ .long = n },
        else => .null,
    };
}

// php_uri_parser_rfc3986_build_from_zval
fn rfcBuild(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, rfc_builder_class ++ "::build", args);
    const base_obj = try a.objectOrNull(0, "baseUrl", rfc_class);
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const scheme = propValue(builderProp(this, rfc_builder_class, "scheme"));
    const userinfo = propValue(builderProp(this, rfc_builder_class, "userinfo"));
    const host = propValue(builderProp(this, rfc_builder_class, "host"));
    const port = propValue(builderProp(this, rfc_builder_class, "port"));
    const path = propValue(builderProp(this, rfc_builder_class, "path"));
    const query = propValue(builderProp(this, rfc_builder_class, "query"));
    const fragment = propValue(builderProp(this, rfc_builder_class, "fragment"));
    const path_text: []const u8 = if (path == .str) path.str else "";
    if (path_text.len > 0) {
        if (scheme == .null) {
            for (path_text) |c| {
                if (c == 0 or c == '/') break;
                if (c == ':') return throwPlain(ctx, invalid_uri_class, "The path must not begin with \":\" when the URI does not contain a scheme");
            }
        }
        if (host == .null and std.mem.startsWith(u8, path_text, "//")) return throwPlain(ctx, invalid_uri_class, "The path must not begin with \"//\" when the URI does not contain a host");
    }
    const al = ctx.vm.allocator;
    var uri: rfc.Uri = .{};
    errdefer uri.deinit(al);
    try rfcWrite(ctx, &uri, .scheme, scheme);
    try rfcWrite(ctx, &uri, .host, host);
    try rfcWrite(ctx, &uri, .username, userinfo);
    try rfcWrite(ctx, &uri, .port, port);
    try rfcWrite(ctx, &uri, .path, .{ .str = path_text });
    try rfcWrite(ctx, &uri, .query, query);
    try rfcWrite(ctx, &uri, .fragment, fragment);
    if (base_obj) |b| {
        const bs = stateOf(b) orelse return error.RuntimeError;
        const combined = rfc.addBase(al, &uri, &bs.body.rfc.uri) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.AddBaseRelBase => return throwPlain(ctx, invalid_uri_class, "The specified base URI must be absolute"),
            else => return throwPlain(ctx, error_class, "Failed to resolve the specified URI against the base URI"),
        };
        uri.deinit(al);
        uri = combined;
    }
    const obj = try ctx.createObject(rfc_class);
    attach(ctx, obj, .{ .rfc = .{ .uri = uri } }) catch |e| {
        discardObject(ctx, obj);
        return e;
    };
    return NativeResult.borrowed(.{ .object = obj });
}

// php_uri_parser_whatwg_build_errors_into_exception: the errors of earlier
// components go before the exception's own
fn errorsIntoException(ctx: *NativeContext, errors: *PhpArray) RuntimeError!void {
    if (errors.entries.items.len == 0) return;
    const exc = ctx.vm.pending_exception orelse return;
    if (exc != .object or !ctx.vm.isInstanceOf(exc.object.class_name, invalid_url_class)) return;
    const own = exc.object.getForScope("errors", invalid_url_class);
    if (own == .array) {
        for (own.array.entries.items) |entry| try errors.append(ctx.allocator, entry.value);
    }
    try exc.object.setForScope(ctx.allocator, "errors", .{ .array = errors }, invalid_url_class);
}

const UrlParts = struct { scheme: RfcValue, username: RfcValue, password: RfcValue, host: RfcValue, port: RfcValue, path: RfcValue, query: RfcValue, fragment: RfcValue };

fn strLen(v: RfcValue) usize {
    return if (v == .str) v.str.len else 0;
}

// php_uri_parser_whatwg_build_path
fn wwBuildPath(ctx: *NativeContext, p: *ww.Parser, url: *ww.Url, parts: UrlParts, errors: *PhpArray) RuntimeError!void {
    const path = if (parts.path == .str) parts.path.str else "";
    var start: usize = 0;
    while (start < path.len and isTabOrNewline(path[start])) start += 1;
    if (url.host.type == .undef and (start == path.len or path[start] != '/')) {
        for (path) |c| if (c == '?' or c == '#') return throwDuringWrite(ctx, p, "path");
        var input: std.ArrayListUnmanaged(u8) = .empty;
        defer input.deinit(ctx.allocator);
        try input.appendSlice(ctx.allocator, path);
        if (strLen(parts.query) > 0) {
            try input.append(ctx.allocator, '?');
        } else if (strLen(parts.fragment) > 0) {
            try input.append(ctx.allocator, '#');
        }
        p.clean();
        const ok = try ww.parseBasic(p, url, null, input.items, .opaque_path);
        if (!ok) {
            throwDuringWrite(ctx, p, "path") catch {};
            _ = try appendLog(ctx, p, errors);
            return error.RuntimeError;
        }
        _ = try appendLog(ctx, p, errors);
        return;
    }
    try urlWrite(ctx, p, url, .path, parts.path);
}

fn wwStep(ctx: *NativeContext, p: *ww.Parser, url: *ww.Url, comptime which: Component, v: RfcValue, errors: *PhpArray) RuntimeError!void {
    const result = urlWrite(ctx, p, url, which, v);
    _ = try appendLog(ctx, p, errors);
    return result;
}

// php_uri_parser_whatwg_resolve_reference_from_zval
fn wwResolveReference(ctx: *NativeContext, p: *ww.Parser, base: *const ww.Url, parts: UrlParts, errors: *PhpArray) RuntimeError!ww.Url {
    const al = ctx.vm.allocator;
    if (parts.host == .str) {
        if (base.path_opaque) return componentError(ctx, "host", .missing_scheme_non_relative_url);
        // a new authority inherits only the scheme
        var with_scheme = parts;
        with_scheme.scheme = .{ .str = base.scheme_name };
        return wwBuildFresh(ctx, p, with_scheme, errors);
    }
    if (strLen(parts.username) > 0) return throwUrlMessage(ctx, "The specified URL cannot have username");
    if (strLen(parts.password) > 0) return throwUrlMessage(ctx, "The specified URL cannot have password");
    if (parts.port == .long) return throwUrlMessage(ctx, "The specified URL cannot have port");
    const path = if (parts.path == .str) parts.path.str else "";
    var first: usize = 0;
    while (first < path.len and isTabOrNewline(path[first])) first += 1;
    var url = try base.clone(al);
    errdefer url.deinit(al);
    if (base.path_opaque and first == path.len and (parts.query == .str or parts.fragment == .null)) {
        if (parts.query == .str) return componentError(ctx, "query", .missing_scheme_non_relative_url);
        return componentError(ctx, "path", .missing_scheme_non_relative_url);
    }
    ww.fragmentSetNull(&url, al);
    if (path.len > 0) {
        var state: ww.State = .no_scheme;
        if (!base.path_opaque and first < path.len and (path[first] == '/' or (ww.isSpecial(base) and path[first] == '\\'))) {
            state = .path_start;
            if (base.scheme_type == .file) {
                var second = first + 1;
                while (second < path.len and isTabOrNewline(path[second])) second += 1;
                if (second == path.len or (path[second] != '/' and path[second] != '\\')) state = .file;
            }
        }
        var reference: std.ArrayListUnmanaged(u8) = .empty;
        defer reference.deinit(ctx.allocator);
        for (path, 0..) |c, i| {
            if (c == '?') {
                try reference.appendSlice(ctx.allocator, "%3F");
            } else if (c == '#') {
                try reference.appendSlice(ctx.allocator, "%23");
                try errors.append(ctx.allocator, .{ .object = try validationError(ctx, .invalid_url_unit, std.mem.sliceTo(path[i..], 0)) });
            } else {
                try reference.append(ctx.allocator, c);
            }
        }
        if (base.path_opaque and first == path.len and parts.query == .null and parts.fragment != .null) {
            try reference.append(ctx.allocator, '#');
        }
        ww.pathSetNull(&url, al);
        p.clean();
        const ok = try ww.parseBasic(p, &url, base, reference.items, state);
        if (!ok) return throwDuringWrite(ctx, p, "path");
        _ = try appendLog(ctx, p, errors);
        if (first < path.len) ww.querySetNull(&url, al);
    }
    if (parts.query == .str) try wwStep(ctx, p, &url, .query, parts.query, errors);
    if (parts.fragment == .str) try wwStep(ctx, p, &url, .fragment, parts.fragment, errors);
    return url;
}

// php_uri_parser_whatwg_get_special_scheme
fn specialScheme(scheme: []const u8) bool {
    var buf: [6]u8 = undefined;
    var len: usize = 0;
    for (scheme) |c| {
        if (isTabOrNewline(c)) continue;
        if (len == buf.len - 1) return false;
        buf[len] = std.ascii.toLower(c);
        len += 1;
    }
    const s = buf[0..len];
    for ([_][]const u8{ "ws", "ftp", "wss", "http", "file", "https" }) |special| {
        if (std.mem.eql(u8, s, special)) return true;
    }
    return false;
}

// php_uri_parser_whatwg_build_from_zval without a base to resolve against
fn wwBuildFresh(ctx: *NativeContext, p: *ww.Parser, parts: UrlParts, errors: *PhpArray) RuntimeError!ww.Url {
    const al = ctx.vm.allocator;
    var url = ww.empty(al);
    errdefer url.deinit(al);
    // a calloc'd url's undefined scheme type would refuse a non-special
    // scheme, so php marks it unknown first
    if (!specialScheme(if (parts.scheme == .str) parts.scheme.str else "")) url.scheme_type = .unknown;
    try wwStep(ctx, p, &url, .scheme, parts.scheme, errors);
    if (parts.host == .str or ww.isSpecial(&url)) try wwStep(ctx, p, &url, .host, parts.host, errors);
    if (url.host.type == .undef or url.host.type == .empty or url.scheme_type == .file) {
        if (strLen(parts.username) > 0) return throwUrlMessage(ctx, "The specified URL cannot have username");
        if (strLen(parts.password) > 0) return throwUrlMessage(ctx, "The specified URL cannot have password");
        if (parts.port != .null) return throwUrlMessage(ctx, "The specified URL cannot have port");
    }
    try wwStep(ctx, p, &url, .username, parts.username, errors);
    try wwStep(ctx, p, &url, .password, parts.password, errors);
    try wwStep(ctx, p, &url, .port, parts.port, errors);
    wwBuildPath(ctx, p, &url, parts, errors) catch |e| {
        _ = try appendLog(ctx, p, errors);
        return e;
    };
    _ = try appendLog(ctx, p, errors);
    try wwStep(ctx, p, &url, .query, parts.query, errors);
    try wwStep(ctx, p, &url, .fragment, parts.fragment, errors);
    return url;
}

fn wwBuild(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const a = Args.init(ctx, whatwg_builder_class ++ "::build", args);
    const base_obj = try a.objectOrNull(0, "baseUrl", whatwg_class);
    const this = thisObject(ctx) orelse return NativeResult.scalar(.null);
    const parts = UrlParts{
        .scheme = propValue(builderProp(this, whatwg_builder_class, "scheme")),
        .username = propValue(builderProp(this, whatwg_builder_class, "username")),
        .password = propValue(builderProp(this, whatwg_builder_class, "password")),
        .host = propValue(builderProp(this, whatwg_builder_class, "host")),
        .port = propValue(builderProp(this, whatwg_builder_class, "port")),
        .path = propValue(builderProp(this, whatwg_builder_class, "path")),
        .query = propValue(builderProp(this, whatwg_builder_class, "query")),
        .fragment = propValue(builderProp(this, whatwg_builder_class, "fragment")),
    };
    const base: ?*const ww.Url = if (base_obj) |b| (if (stateOf(b)) |s| &s.body.whatwg else null) else null;
    var p = ww.Parser.init(ctx.vm.allocator);
    defer p.deinit();
    const errors = try ctx.createArray();
    errors.retain();
    defer ctx.vm.releaseValue(.{ .array = errors });
    const scheme_empty = parts.scheme == .str and parts.scheme.str.len == 0;
    const built = (if (base != null and scheme_empty)
        wwResolveReference(ctx, &p, base.?, parts, errors)
    else
        wwBuildFresh(ctx, &p, parts, errors)) catch |e| {
        if (e == error.RuntimeError) {
            try errorsIntoException(ctx, errors);
            const exc = ctx.vm.takePending();
            defer if (exc) |x| ctx.vm.setPendingOwned(x);
            if (args.len > 1) ctx.setCallerVar(1, args.len, try emptyArray(ctx));
        }
        return e;
    };
    var url = built;
    if (args.len > 1) {
        ctx.setCallerVar(1, args.len, .{ .array = errors });
        if (ctx.vm.pending_exception != null) {
            url.deinit(ctx.vm.allocator);
            return error.RuntimeError;
        }
    }
    const obj = try ctx.createObject(whatwg_class);
    attach(ctx, obj, .{ .whatwg = url }) catch |e| {
        url.deinit(ctx.vm.allocator);
        discardObject(ctx, obj);
        return e;
    };
    return NativeResult.borrowed(.{ .object = obj });
}

// ---- registration ------------------------------------------------------------------------

fn addMethods(vm: *VM, a: Allocator, def: *ClassDef, comptime class: []const u8, comptime methods: anytype) !void {
    inline for (methods) |m| {
        const is_static = comptime std.mem.eql(u8, m[0], "parse");
        try def.methods.put(a, m[0], .{ .name = m[0], .arity = m[1], .is_static = is_static });
        try vm.native_fns.put(a, class ++ "::" ++ m[0], m[2]);
    }
}

pub fn register(vm: *VM, a: Allocator) !void {
    // exceptions
    try vm.classes.put(a, exception_class, .{ .name = exception_class, .parent = "Exception", .no_dynamic_properties = true });
    try vm.classes.put(a, error_class, .{ .name = error_class, .parent = "Error", .no_dynamic_properties = true });
    try vm.classes.put(a, invalid_uri_class, .{ .name = invalid_uri_class, .parent = exception_class, .no_dynamic_properties = true });
    var invalid_url = ClassDef{ .name = invalid_url_class, .parent = invalid_uri_class, .no_dynamic_properties = true };
    try invalid_url.properties.append(a, .{ .name = "errors", .default = .undef, .is_readonly = true, .type_str = "array" });
    invalid_url.slot_layout = try vm.buildSlotLayout(&invalid_url);
    try addMethods(vm, a, &invalid_url, invalid_url_class, .{.{ "__construct", 4, invalidUrlExceptionConstruct }});
    try vm.classes.put(a, invalid_url_class, invalid_url);

    try vm.registerUnitEnum(comparison_mode_class, &.{ "IncludeFragment", "ExcludeFragment" });
    try vm.registerUnitEnum(uri_type_class, &.{ "AbsolutePathReference", "RelativePathReference", "NetworkPathReference", "Uri" });
    try vm.registerUnitEnum(rfc_host_type_class, &.{ "IpV4", "IpV6", "IpVFuture", "RegisteredName" });
    try vm.registerUnitEnum(validation_error_type_class, &validation_error_types);
    try vm.registerUnitEnum(whatwg_host_type_class, &.{ "IpV4", "IpV6", "Domain", "Opaque", "Empty" });
    try vm.registerUnitEnum(percent_mode_class, &percent_modes);

    var verr = ClassDef{ .name = validation_error_class, .is_final = true, .is_readonly = true, .no_dynamic_properties = true };
    try verr.properties.append(a, .{ .name = "context", .default = .undef, .is_readonly = true, .type_str = "string" });
    try verr.properties.append(a, .{ .name = "type", .default = .undef, .is_readonly = true, .type_str = validation_error_type_class });
    try verr.properties.append(a, .{ .name = "failure", .default = .undef, .is_readonly = true, .type_str = "bool" });
    verr.slot_layout = try vm.buildSlotLayout(&verr);
    try addMethods(vm, a, &verr, validation_error_class, .{.{ "__construct", 3, validationErrorConstruct }});
    try vm.classes.put(a, validation_error_class, verr);

    // Uri\Rfc3986\UriBuilder
    const rfc_props = [_][]const u8{ "scheme", "userinfo", "host", "port", "path", "query", "fragment" };
    var rb = ClassDef{ .name = rfc_builder_class, .is_final = true, .no_dynamic_properties = true };
    for (rfc_props) |name| {
        const is_path = std.mem.eql(u8, name, "path");
        const t: []const u8 = if (is_path) "string" else if (std.mem.eql(u8, name, "port")) "?int" else "?string";
        try rb.properties.append(a, .{ .name = name, .default = if (is_path) .{ .string = Value.String.borrowed("") } else .null, .has_default = true, .visibility = .private, .type_str = t });
    }
    rb.slot_layout = try vm.buildSlotLayout(&rb);
    try addMethods(vm, a, &rb, rfc_builder_class, .{
        .{ "reset", 0, builderReset(rfc_builder_class, &.{"path"}, &rfc_props) },
        .{ "setScheme", 1, builderSetter(rfc_builder_class, "setScheme", "scheme", .str_or_null, "scheme", .rfc_scheme) },
        .{ "setUserInfo", 1, builderSetter(rfc_builder_class, "setUserInfo", "userinfo", .str_or_null, "userInfo", .rfc_userinfo) },
        .{ "setHost", 1, builderSetter(rfc_builder_class, "setHost", "host", .str_or_null, "host", .rfc_host) },
        .{ "setPort", 1, builderSetter(rfc_builder_class, "setPort", "port", .long_or_null, "port", .rfc_port) },
        .{ "setPath", 1, builderSetter(rfc_builder_class, "setPath", "path", .str, "path", .rfc_path) },
        .{ "setQuery", 1, builderSetter(rfc_builder_class, "setQuery", "query", .str_or_null, "query", .rfc_query) },
        .{ "setFragment", 1, builderSetter(rfc_builder_class, "setFragment", "fragment", .str_or_null, "fragment", .rfc_fragment) },
        .{ "build", 1, rfcBuild },
    });
    try vm.classes.put(a, rfc_builder_class, rb);

    // Uri\Rfc3986\Uri
    var ru = ClassDef{ .name = rfc_class, .is_final = true, .is_readonly = true, .no_dynamic_properties = true, .native_cleanup = cleanupUri, .native_clone = cloneUri };
    try addMethods(vm, a, &ru, rfc_class, .{
        .{ "parse", 2, rfcParseStatic },
        .{ "__construct", 2, rfcConstruct },
        .{ "getUriType", 0, rfcGetUriType },
        .{ "getScheme", 0, rfcGetter(.scheme, .normalized) },
        .{ "getRawScheme", 0, rfcGetter(.scheme, .raw) },
        .{ "withScheme", 1, rfcWither("withScheme", .scheme, .str_or_null, "scheme") },
        .{ "getUserInfo", 0, rfcUserInfoGetter(.normalized) },
        .{ "getRawUserInfo", 0, rfcUserInfoGetter(.raw) },
        .{ "withUserInfo", 1, rfcWither("withUserInfo", .username, .str_or_null, "userinfo") },
        .{ "getUsername", 0, rfcGetter(.username, .normalized) },
        .{ "getRawUsername", 0, rfcGetter(.username, .raw) },
        .{ "getPassword", 0, rfcGetter(.password, .normalized) },
        .{ "getRawPassword", 0, rfcGetter(.password, .raw) },
        .{ "getHost", 0, rfcGetter(.host, .normalized) },
        .{ "getRawHost", 0, rfcGetter(.host, .raw) },
        .{ "getHostType", 0, rfcGetHostType },
        .{ "withHost", 1, rfcWither("withHost", .host, .str_or_null, "host") },
        .{ "getPort", 0, rfcGetter(.port, .raw) },
        .{ "withPort", 1, rfcWither("withPort", .port, .long_or_null, "port") },
        .{ "getPath", 0, rfcGetter(.path, .normalized) },
        .{ "getRawPath", 0, rfcGetter(.path, .raw) },
        .{ "withPath", 1, rfcWither("withPath", .path, .str, "path") },
        .{ "getQuery", 0, rfcGetter(.query, .normalized) },
        .{ "getRawQuery", 0, rfcGetter(.query, .raw) },
        .{ "withQuery", 1, rfcWither("withQuery", .query, .str_or_null, "query") },
        .{ "getFragment", 0, rfcGetter(.fragment, .normalized) },
        .{ "getRawFragment", 0, rfcGetter(.fragment, .raw) },
        .{ "withFragment", 1, rfcWither("withFragment", .fragment, .str_or_null, "fragment") },
        .{ "equals", 2, rfcEquals },
        .{ "toString", 0, rfcToStringMethod(.normalized) },
        .{ "toRawString", 0, rfcToStringMethod(.raw) },
        .{ "resolve", 1, rfcResolve },
        .{ "__serialize", 0, serializeUri },
        .{ "__unserialize", 1, unserializeUri },
        .{ "__debugInfo", 0, debugInfo },
    });
    try vm.classes.put(a, rfc_class, ru);

    // Uri\WhatWg\UrlBuilder
    const ww_props = [_][]const u8{ "scheme", "username", "password", "host", "port", "path", "query", "fragment" };
    var wb = ClassDef{ .name = whatwg_builder_class, .is_final = true };
    for (ww_props) |name| {
        const is_string = std.mem.eql(u8, name, "path") or std.mem.eql(u8, name, "scheme");
        const t: []const u8 = if (is_string) "string" else if (std.mem.eql(u8, name, "port")) "?int" else "?string";
        try wb.properties.append(a, .{ .name = name, .default = if (is_string) .{ .string = Value.String.borrowed("") } else .null, .has_default = true, .visibility = .private, .type_str = t });
    }
    wb.slot_layout = try vm.buildSlotLayout(&wb);
    try addMethods(vm, a, &wb, whatwg_builder_class, .{
        .{ "reset", 0, builderReset(whatwg_builder_class, &.{ "scheme", "path" }, &ww_props) },
        .{ "setScheme", 1, builderSetter(whatwg_builder_class, "setScheme", "scheme", .str, "scheme", .ww_scheme) },
        .{ "setUsername", 1, builderSetter(whatwg_builder_class, "setUsername", "username", .str_or_null, "username", .none) },
        .{ "setPassword", 1, builderSetter(whatwg_builder_class, "setPassword", "password", .str_or_null, "password", .none) },
        .{ "setHost", 1, builderSetter(whatwg_builder_class, "setHost", "host", .str_or_null, "host", .ww_host) },
        .{ "setPort", 1, builderSetter(whatwg_builder_class, "setPort", "port", .long_or_null, "port", .ww_port) },
        .{ "setPath", 1, builderSetter(whatwg_builder_class, "setPath", "path", .str, "path", .none) },
        .{ "setQuery", 1, builderSetter(whatwg_builder_class, "setQuery", "query", .str_or_null, "query", .none) },
        .{ "setFragment", 1, builderSetter(whatwg_builder_class, "setFragment", "fragment", .str_or_null, "fragment", .none) },
        .{ "build", 2, wwBuild },
    });
    try vm.classes.put(a, whatwg_builder_class, wb);

    // Uri\WhatWg\Url
    var wu = ClassDef{ .name = whatwg_class, .is_final = true, .is_readonly = true, .no_dynamic_properties = true, .native_cleanup = cleanupUri, .native_clone = cloneUri };
    try addMethods(vm, a, &wu, whatwg_class, .{
        .{ "parse", 3, urlParseStatic },
        .{ "__construct", 3, urlConstruct },
        .{ "getScheme", 0, urlGetter(.scheme, .ascii) },
        .{ "withScheme", 1, urlWither("withScheme", .scheme, .str, "scheme") },
        .{ "isSpecialScheme", 0, urlIsSpecialScheme },
        .{ "getUsername", 0, urlGetter(.username, .ascii) },
        .{ "withUsername", 1, urlWither("withUsername", .username, .str_or_null, "username") },
        .{ "getPassword", 0, urlGetter(.password, .ascii) },
        .{ "withPassword", 1, urlWither("withPassword", .password, .str_or_null, "password") },
        .{ "getAsciiHost", 0, urlGetter(.host, .ascii) },
        .{ "getUnicodeHost", 0, urlGetter(.host, .unicode) },
        .{ "getHostType", 0, urlGetHostType },
        .{ "withHost", 1, urlWither("withHost", .host, .str_or_null, "host") },
        .{ "getPort", 0, urlGetter(.port, .ascii) },
        .{ "withPort", 1, urlWither("withPort", .port, .long_or_null, "port") },
        .{ "getPath", 0, urlGetter(.path, .ascii) },
        .{ "withPath", 1, urlWither("withPath", .path, .str, "path") },
        .{ "getQuery", 0, urlGetter(.query, .ascii) },
        .{ "withQuery", 1, urlWither("withQuery", .query, .str_or_null, "query") },
        .{ "getFragment", 0, urlGetter(.fragment, .ascii) },
        .{ "withFragment", 1, urlWither("withFragment", .fragment, .str_or_null, "fragment") },
        .{ "equals", 2, urlEquals },
        .{ "toAsciiString", 0, urlToAsciiString },
        .{ "toUnicodeString", 0, urlToUnicodeString },
        .{ "resolve", 2, urlResolve },
        .{ "__serialize", 0, serializeUri },
        .{ "__unserialize", 1, unserializeUri },
        .{ "__debugInfo", 0, debugInfo },
    });
    try vm.classes.put(a, whatwg_class, wu);
}
