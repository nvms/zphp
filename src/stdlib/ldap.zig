const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cDefine("LDAP_DEPRECATED", "1");
    @cInclude("ldap.h");
});

pub const entries = .{
    .{ "ldap_connect", native_connect },
    .{ "ldap_bind", native_bind },
    .{ "ldap_bind_ext", native_bind },
    .{ "ldap_unbind", native_unbind },
    .{ "ldap_close", native_unbind },
    .{ "ldap_search", native_search },
    .{ "ldap_list", native_list },
    .{ "ldap_read", native_read },
    .{ "ldap_get_entries", native_get_entries },
    .{ "ldap_count_entries", native_count_entries },
    .{ "ldap_add", native_add },
    .{ "ldap_modify", native_modify },
    .{ "ldap_mod_replace", native_modify },
    .{ "ldap_mod_add", native_mod_add },
    .{ "ldap_mod_del", native_mod_del },
    .{ "ldap_delete", native_delete },
    .{ "ldap_rename", native_rename },
    .{ "ldap_compare", native_compare },
    .{ "ldap_set_option", native_set_option },
    .{ "ldap_get_option", native_get_option },
    .{ "ldap_err2str", native_err2str },
    .{ "ldap_errno", native_errno },
    .{ "ldap_error", native_error },
    .{ "ldap_start_tls", native_start_tls },
    .{ "ldap_escape", native_escape },
    .{ "ldap_free_result", native_free_result },
    .{ "ldap_explode_dn", native_explode_dn },
    .{ "ldap_dn2ufn", native_dn2ufn },
    .{ "ldap_count_references", native_count_references },
};

fn getLdap(obj: *PhpObject) ?*c.LDAP {
    const v = obj.get("__ptr");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn getHandle(args: []const Value, expect: []const u8) ?*PhpObject {
    if (args.len < 1 or args[0] != .object) return null;
    const o = args[0].object;
    if (!std.mem.eql(u8, o.class_name, expect)) return null;
    return o;
}

fn getResult(obj: *PhpObject) ?*c.LDAPMessage {
    const v = obj.get("__ptr");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn cstrToOwned(ctx: *NativeContext, p: ?[*:0]const u8) RuntimeError!Value {
    if (p == null) return .{ .string = "" };
    const s = std.mem.span(p.?);
    const owned = try ctx.allocator.dupe(u8, s);
    try ctx.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn native_connect(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    var uri_buf: [512]u8 = undefined;
    var uri_slice: []const u8 = "ldap://localhost:389";

    if (args.len >= 1 and args[0] == .string) {
        const a0 = args[0].string;
        if (std.mem.indexOf(u8, a0, "://") != null) {
            uri_slice = std.fmt.bufPrint(&uri_buf, "{s}", .{a0}) catch return .{ .bool = false };
        } else {
            const port: u16 = if (args.len > 1 and args[1] == .int) @intCast(args[1].int) else 389;
            uri_slice = std.fmt.bufPrint(&uri_buf, "ldap://{s}:{d}", .{ a0, port }) catch return .{ .bool = false };
        }
    }

    const uri_z = try ctx.allocator.dupeZ(u8, uri_slice);
    defer ctx.allocator.free(uri_z);
    var ldap_ptr: ?*c.LDAP = null;
    if (c.ldap_initialize(&ldap_ptr, uri_z.ptr) != c.LDAP_SUCCESS or ldap_ptr == null) return .{ .bool = false };

    // protocol version 3 by default (matches PHP)
    var version: c_int = 3;
    _ = c.ldap_set_option(ldap_ptr, c.LDAP_OPT_PROTOCOL_VERSION, &version);

    const obj = try ctx.createObject("LDAP\\Connection");
    try obj.set(ctx.allocator, "__ptr", .{ .int = @intCast(@intFromPtr(ldap_ptr)) });
    return .{ .object = obj };
}

fn native_bind(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    const dn: [*:0]const u8 = if (args.len > 1 and args[1] == .string)
        (try ctx.allocator.dupeZ(u8, args[1].string)).ptr
    else
        "";
    const pw: [*:0]const u8 = if (args.len > 2 and args[2] == .string)
        (try ctx.allocator.dupeZ(u8, args[2].string)).ptr
    else
        "";
    const rc = c.ldap_simple_bind_s(ld, dn, pw);
    if (rc != c.LDAP_SUCCESS) {
        try o.set(ctx.allocator, "__errno", .{ .int = @intCast(rc) });
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_unbind(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = true };
    _ = c.ldap_unbind_ext_s(ld, null, null);
    o.set(std.heap.page_allocator, "__ptr", .{ .int = 0 }) catch {};
    return .{ .bool = true };
}

fn doSearch(ctx: *NativeContext, args: []const Value, scope: c_int) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    if (args.len < 3) return .{ .bool = false };
    const base = if (args[1] == .string) args[1].string else "";
    const filter = if (args[2] == .string) args[2].string else "(objectClass=*)";
    const base_z = try ctx.allocator.dupeZ(u8, base);
    defer ctx.allocator.free(base_z);
    const filter_z = try ctx.allocator.dupeZ(u8, filter);
    defer ctx.allocator.free(filter_z);

    var attrs_storage = std.ArrayListUnmanaged([*c]u8){};
    defer {
        for (attrs_storage.items) |p| if (p) |pp| ctx.allocator.free(std.mem.span(pp));
        attrs_storage.deinit(ctx.allocator);
    }
    if (args.len > 3 and args[3] == .array) {
        for (args[3].array.entries.items) |entry| {
            if (entry.value != .string) continue;
            const s = try ctx.allocator.dupeZ(u8, entry.value.string);
            try attrs_storage.append(ctx.allocator, s.ptr);
        }
        try attrs_storage.append(ctx.allocator, null);
    }
    const attrs_ptr: [*c][*c]u8 = if (attrs_storage.items.len > 0) attrs_storage.items.ptr else null;

    var result: ?*c.LDAPMessage = null;
    const rc = c.ldap_search_ext_s(ld, base_z.ptr, scope, filter_z.ptr, attrs_ptr, 0, null, null, null, 0, &result);
    if (rc != c.LDAP_SUCCESS) {
        try o.set(ctx.allocator, "__errno", .{ .int = @intCast(rc) });
        if (result) |r| _ = c.ldap_msgfree(r);
        return .{ .bool = false };
    }
    const obj = try ctx.createObject("LDAP\\Result");
    try obj.set(ctx.allocator, "__ptr", .{ .int = @intCast(@intFromPtr(result)) });
    try obj.set(ctx.allocator, "__ld", .{ .int = @intCast(@intFromPtr(ld)) });
    return .{ .object = obj };
}

fn native_search(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return doSearch(ctx, args, c.LDAP_SCOPE_SUBTREE);
}
fn native_list(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return doSearch(ctx, args, c.LDAP_SCOPE_ONELEVEL);
}
fn native_read(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return doSearch(ctx, args, c.LDAP_SCOPE_BASE);
}

fn native_count_entries(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .object) return .{ .bool = false };
    const conn = getHandle(args[0..1], "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(conn) orelse return .{ .bool = false };
    const ro = args[1].object;
    if (!std.mem.eql(u8, ro.class_name, "LDAP\\Result")) return .{ .bool = false };
    const r = getResult(ro) orelse return .{ .int = 0 };
    return .{ .int = @intCast(c.ldap_count_entries(ld, r)) };
}

fn native_get_entries(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[1] != .object) return .{ .bool = false };
    const conn = getHandle(args[0..1], "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(conn) orelse return .{ .bool = false };
    const ro = args[1].object;
    if (!std.mem.eql(u8, ro.class_name, "LDAP\\Result")) return .{ .bool = false };
    const r = getResult(ro) orelse return .{ .bool = false };

    const arr = try ctx.createArray();
    var count: i64 = 0;
    var entry: ?*c.LDAPMessage = c.ldap_first_entry(ld, r);
    var idx: i64 = 0;
    while (entry != null) : ({
        entry = c.ldap_next_entry(ld, entry);
        idx += 1;
        count += 1;
    }) {
        const e_arr = try ctx.createArray();
        const dn = c.ldap_get_dn(ld, entry);
        if (dn) |d| {
            const dn_s = std.mem.span(d);
            const owned = try ctx.allocator.dupe(u8, dn_s);
            try ctx.strings.append(ctx.allocator, owned);
            try e_arr.set(ctx.allocator, .{ .string = "dn" }, .{ .string = owned });
            c.ldap_memfree(d);
        }

        var ber: ?*c.BerElement = null;
        var attr: ?[*:0]u8 = c.ldap_first_attribute(ld, entry, &ber);
        var attr_count: i64 = 0;
        while (attr != null) : ({
            c.ldap_memfree(attr);
            attr = c.ldap_next_attribute(ld, entry, ber);
        }) {
            const attr_name = std.mem.span(attr.?);
            const lower_name = try ctx.allocator.dupe(u8, attr_name);
            for (lower_name) |*ch| ch.* = std.ascii.toLower(ch.*);
            try ctx.strings.append(ctx.allocator, lower_name);

            const values = c.ldap_get_values_len(ld, entry, attr_name);
            const v_arr = try ctx.createArray();
            var vlen: i64 = 0;
            if (values != null) {
                var i: usize = 0;
                while (values[i] != null) : (i += 1) {
                    const bv = values[i];
                    const data = bv.*.bv_val[0..@as(usize, @intCast(bv.*.bv_len))];
                    const owned_v = try ctx.allocator.dupe(u8, data);
                    try ctx.strings.append(ctx.allocator, owned_v);
                    try v_arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .string = owned_v });
                    vlen += 1;
                }
                c.ldap_value_free_len(values);
            }
            try v_arr.set(ctx.allocator, .{ .string = "count" }, .{ .int = vlen });
            try e_arr.set(ctx.allocator, .{ .string = lower_name }, .{ .array = v_arr });
            try e_arr.set(ctx.allocator, .{ .int = attr_count }, .{ .string = lower_name });
            attr_count += 1;
        }
        if (ber) |b| c.ber_free(b, 0);
        try e_arr.set(ctx.allocator, .{ .string = "count" }, .{ .int = attr_count });
        try arr.set(ctx.allocator, .{ .int = idx }, .{ .array = e_arr });
    }
    try arr.set(ctx.allocator, .{ .string = "count" }, .{ .int = count });
    return .{ .array = arr };
}

fn buildLDAPMods(ctx: *NativeContext, dict: *const PhpArray, op: c_int) ![]?*c.LDAPMod {
    var list = std.ArrayListUnmanaged(?*c.LDAPMod){};
    errdefer list.deinit(ctx.allocator);
    for (dict.entries.items) |entry| {
        const attr_name = switch (entry.key) {
            .string => |s| s,
            else => continue,
        };
        const attr_z = try ctx.allocator.dupeZ(u8, attr_name);

        var vals_storage = std.ArrayListUnmanaged([*c]u8){};
        errdefer vals_storage.deinit(ctx.allocator);

        switch (entry.value) {
            .array => |inner| {
                for (inner.entries.items) |ie| {
                    if (ie.value != .string) continue;
                    const sz = try ctx.allocator.dupeZ(u8, ie.value.string);
                    try vals_storage.append(ctx.allocator, sz.ptr);
                }
            },
            .string => |s| {
                const sz = try ctx.allocator.dupeZ(u8, s);
                try vals_storage.append(ctx.allocator, sz.ptr);
            },
            else => {},
        }
        try vals_storage.append(ctx.allocator, null);

        const mod = try ctx.allocator.create(c.LDAPMod);
        mod.* = .{
            .mod_op = op,
            .mod_type = attr_z.ptr,
            .mod_vals = .{ .modv_strvals = (try vals_storage.toOwnedSlice(ctx.allocator)).ptr },
        };
        try list.append(ctx.allocator, mod);
    }
    try list.append(ctx.allocator, null);
    return try list.toOwnedSlice(ctx.allocator);
}

fn doMod(ctx: *NativeContext, args: []const Value, op: c_int) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    if (args.len < 3 or args[1] != .string or args[2] != .array) return .{ .bool = false };
    const dn_z = try ctx.allocator.dupeZ(u8, args[1].string);
    defer ctx.allocator.free(dn_z);
    const mods = buildLDAPMods(ctx, args[2].array, op) catch return .{ .bool = false };
    const rc = c.ldap_modify_ext_s(ld, dn_z.ptr, @ptrCast(mods.ptr), null, null);
    if (rc != c.LDAP_SUCCESS) {
        try o.set(ctx.allocator, "__errno", .{ .int = @intCast(rc) });
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_add(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    if (args.len < 3 or args[1] != .string or args[2] != .array) return .{ .bool = false };
    const dn_z = try ctx.allocator.dupeZ(u8, args[1].string);
    defer ctx.allocator.free(dn_z);
    const mods = buildLDAPMods(ctx, args[2].array, 0) catch return .{ .bool = false };
    const rc = c.ldap_add_ext_s(ld, dn_z.ptr, @ptrCast(mods.ptr), null, null);
    if (rc != c.LDAP_SUCCESS) {
        try o.set(ctx.allocator, "__errno", .{ .int = @intCast(rc) });
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_modify(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return doMod(ctx, args, c.LDAP_MOD_REPLACE);
}
fn native_mod_add(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return doMod(ctx, args, c.LDAP_MOD_ADD);
}
fn native_mod_del(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    return doMod(ctx, args, c.LDAP_MOD_DELETE);
}

fn native_delete(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    if (args.len < 2 or args[1] != .string) return .{ .bool = false };
    const dn_z = try ctx.allocator.dupeZ(u8, args[1].string);
    defer ctx.allocator.free(dn_z);
    const rc = c.ldap_delete_ext_s(ld, dn_z.ptr, null, null);
    if (rc != c.LDAP_SUCCESS) {
        try o.set(ctx.allocator, "__errno", .{ .int = @intCast(rc) });
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_rename(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    if (args.len < 5) return .{ .bool = false };
    const dn = if (args[1] == .string) args[1].string else return .{ .bool = false };
    const newrdn = if (args[2] == .string) args[2].string else return .{ .bool = false };
    const newparent: ?[*:0]const u8 = if (args[3] == .string) (try ctx.allocator.dupeZ(u8, args[3].string)).ptr else null;
    const delete_old: c_int = if (args[4] == .bool) (if (args[4].bool) 1 else 0) else 0;
    const dn_z = try ctx.allocator.dupeZ(u8, dn);
    defer ctx.allocator.free(dn_z);
    const new_z = try ctx.allocator.dupeZ(u8, newrdn);
    defer ctx.allocator.free(new_z);
    const rc = c.ldap_rename_s(ld, dn_z.ptr, new_z.ptr, newparent, delete_old, null, null);
    if (rc != c.LDAP_SUCCESS) {
        try o.set(ctx.allocator, "__errno", .{ .int = @intCast(rc) });
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_compare(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .int = -1 };
    const ld = getLdap(o) orelse return .{ .int = -1 };
    if (args.len < 4 or args[1] != .string or args[2] != .string or args[3] != .string) return .{ .int = -1 };
    const dn_z = try ctx.allocator.dupeZ(u8, args[1].string);
    defer ctx.allocator.free(dn_z);
    const attr_z = try ctx.allocator.dupeZ(u8, args[2].string);
    defer ctx.allocator.free(attr_z);
    var bval = c.berval{ .bv_len = args[3].string.len, .bv_val = @constCast(args[3].string.ptr) };
    const rc = c.ldap_compare_ext_s(ld, dn_z.ptr, attr_z.ptr, &bval, null, null);
    if (rc == c.LDAP_COMPARE_TRUE) return .{ .bool = true };
    if (rc == c.LDAP_COMPARE_FALSE) return .{ .bool = false };
    return .{ .int = -1 };
}

fn native_set_option(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .object or args[1] != .int) return .{ .bool = false };
    const o = getHandle(args[0..1], "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    const opt: c_int = @intCast(args[1].int);
    switch (args[2]) {
        .int, .bool => {
            var v: c_int = if (args[2] == .int) @intCast(args[2].int) else @intFromBool(args[2].bool);
            return .{ .bool = c.ldap_set_option(ld, opt, &v) == c.LDAP_OPT_SUCCESS };
        },
        .string => {
            const sz = try ctx.allocator.dupeZ(u8, args[2].string);
            defer ctx.allocator.free(sz);
            return .{ .bool = c.ldap_set_option(ld, opt, sz.ptr) == c.LDAP_OPT_SUCCESS };
        },
        else => return .{ .bool = false },
    }
}

fn native_get_option(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .object or args[1] != .int) return .{ .bool = false };
    const o = getHandle(args[0..1], "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    const opt: c_int = @intCast(args[1].int);
    var v: c_int = 0;
    if (c.ldap_get_option(ld, opt, &v) != c.LDAP_OPT_SUCCESS) return .{ .bool = false };
    ctx.setCallerVar(2, args.len, .{ .int = @intCast(v) });
    return .{ .bool = true };
}

fn native_err2str(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .string = "" };
    const s = c.ldap_err2string(@intCast(args[0].int));
    return try cstrToOwned(ctx, s);
}

fn native_errno(_: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .int = 0 };
    const v = o.get("__errno");
    if (v == .int) return v;
    return .{ .int = 0 };
}

fn native_error(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const v = try native_errno(ctx, args);
    return try native_err2str(ctx, &[_]Value{v});
}

fn native_start_tls(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const o = getHandle(args, "LDAP\\Connection") orelse return .{ .bool = false };
    const ld = getLdap(o) orelse return .{ .bool = false };
    const rc = c.ldap_start_tls_s(ld, null, null);
    if (rc != c.LDAP_SUCCESS) {
        try o.set(ctx.allocator, "__errno", .{ .int = @intCast(rc) });
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn native_escape(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .string = "" };
    const v = args[0].string;
    const ignore: []const u8 = if (args.len > 1 and args[1] == .string) args[1].string else "";
    const flags: i64 = if (args.len > 2 and args[2] == .int) args[2].int else 0;
    const flag_filter: bool = (flags & 1) != 0;
    const flag_dn: bool = (flags & 2) != 0;
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(ctx.allocator);
    for (v) |ch| {
        var must_escape = false;
        // when flags are set, only escape per spec; when not, escape both sets
        if (flag_filter or (!flag_filter and !flag_dn)) {
            if (ch == 0 or ch == '*' or ch == '(' or ch == ')' or ch == '\\') must_escape = true;
        }
        if (flag_dn or (!flag_filter and !flag_dn)) {
            if (ch == ',' or ch == '=' or ch == '+' or ch == '<' or ch == '>' or ch == ';' or ch == '"' or ch == '#' or ch == '\\') must_escape = true;
        }
        if (std.mem.indexOfScalar(u8, ignore, ch) != null) must_escape = false;
        if (must_escape) {
            try out.appendSlice(ctx.allocator, "\\");
            const hex = "0123456789abcdef";
            try out.append(ctx.allocator, hex[ch >> 4]);
            try out.append(ctx.allocator, hex[ch & 0xf]);
        } else try out.append(ctx.allocator, ch);
    }
    const owned = try out.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn native_free_result(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const o = args[0].object;
    if (!std.mem.eql(u8, o.class_name, "LDAP\\Result")) return .{ .bool = false };
    const r = getResult(o) orelse return .{ .bool = true };
    _ = c.ldap_msgfree(r);
    o.set(std.heap.page_allocator, "__ptr", .{ .int = 0 }) catch {};
    return .{ .bool = true };
}

fn native_explode_dn(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const with_attrib: c_int = if (args.len > 1 and args[1] == .int) @intCast(args[1].int) else 1;
    const dn_z = try ctx.allocator.dupeZ(u8, args[0].string);
    defer ctx.allocator.free(dn_z);
    const parts = c.ldap_explode_dn(dn_z.ptr, with_attrib);
    if (parts == null) return .{ .bool = false };
    defer c.ldap_memvfree(@ptrCast(parts));
    const arr = try ctx.createArray();
    var i: usize = 0;
    while (parts[i] != null) : (i += 1) {
        const s = std.mem.span(parts[i]);
        const owned = try ctx.allocator.dupe(u8, s);
        try ctx.strings.append(ctx.allocator, owned);
        try arr.set(ctx.allocator, .{ .int = @intCast(i) }, .{ .string = owned });
    }
    try arr.set(ctx.allocator, .{ .string = "count" }, .{ .int = @intCast(i) });
    return .{ .array = arr };
}

fn native_dn2ufn(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const dn_z = try ctx.allocator.dupeZ(u8, args[0].string);
    defer ctx.allocator.free(dn_z);
    const ufn = c.ldap_dn2ufn(dn_z.ptr);
    if (ufn == null) return .{ .bool = false };
    defer c.ldap_memfree(ufn);
    return try cstrToOwned(ctx, ufn);
}

fn native_count_references(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "LDAP\\Connection")) {
            const v = obj.get("__ptr");
            if (v == .int and v.int != 0) {
                const ld: *c.LDAP = @ptrFromInt(@as(usize, @intCast(v.int)));
                _ = c.ldap_unbind_ext_s(ld, null, null);
            }
        } else if (std.mem.eql(u8, obj.class_name, "LDAP\\Result")) {
            const v = obj.get("__ptr");
            if (v == .int and v.int != 0) {
                const r: *c.LDAPMessage = @ptrFromInt(@as(usize, @intCast(v.int)));
                _ = c.ldap_msgfree(r);
            }
        }
    }
}

test {}
