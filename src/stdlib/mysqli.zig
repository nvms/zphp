// mysqli — real implementation backed by libmysqlclient.
//
// shares the C-API binding shape with pdo_mysql.zig (same library, same
// extern declarations) but exposes a separate API surface modeled on the
// procedural mysqli_* functions and the mysqli / mysqli_result / mysqli_stmt
// classes. WordPress core, phpMyAdmin, MediaWiki, Drupal, and any framework
// that pre-dates PDO calls into this directly.

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

const mysql = struct {
    const MYSQL = opaque {};
    const MYSQL_RES = opaque {};
    const MYSQL_FIELD = opaque {};

    extern "mysqlclient" fn mysql_init(m: ?*MYSQL) callconv(.c) ?*MYSQL;
    extern "mysqlclient" fn mysql_real_connect(m: *MYSQL, host: ?[*:0]const u8, user: ?[*:0]const u8, passwd: ?[*:0]const u8, db: ?[*:0]const u8, port: c_uint, socket: ?[*:0]const u8, flags: c_ulong) callconv(.c) ?*MYSQL;
    extern "mysqlclient" fn mysql_close(m: *MYSQL) callconv(.c) void;
    extern "mysqlclient" fn mysql_error(m: *MYSQL) callconv(.c) [*:0]const u8;
    extern "mysqlclient" fn mysql_errno(m: *MYSQL) callconv(.c) c_uint;
    extern "mysqlclient" fn mysql_real_query(m: *MYSQL, q: [*]const u8, len: c_ulong) callconv(.c) c_int;
    extern "mysqlclient" fn mysql_store_result(m: *MYSQL) callconv(.c) ?*MYSQL_RES;
    extern "mysqlclient" fn mysql_affected_rows(m: *MYSQL) callconv(.c) u64;
    extern "mysqlclient" fn mysql_insert_id(m: *MYSQL) callconv(.c) u64;
    extern "mysqlclient" fn mysql_num_fields(res: *MYSQL_RES) callconv(.c) c_uint;
    extern "mysqlclient" fn mysql_field_seek(res: *MYSQL_RES, offset: c_uint) callconv(.c) c_uint;
    extern "mysqlclient" fn mysql_fetch_field(res: *MYSQL_RES) callconv(.c) ?*MYSQL_FIELD;
    extern "mysqlclient" fn mysql_fetch_row(res: *MYSQL_RES) callconv(.c) ?[*]?[*:0]const u8;
    extern "mysqlclient" fn mysql_fetch_lengths(res: *MYSQL_RES) callconv(.c) ?[*]c_ulong;
    extern "mysqlclient" fn mysql_free_result(res: *MYSQL_RES) callconv(.c) void;
    extern "mysqlclient" fn mysql_num_rows(res: *MYSQL_RES) callconv(.c) u64;
    extern "mysqlclient" fn mysql_real_escape_string(m: *MYSQL, to: [*]u8, from: [*]const u8, length: c_ulong) callconv(.c) c_ulong;
    extern "mysqlclient" fn mysql_autocommit(m: *MYSQL, auto_mode: u8) callconv(.c) u8;
    extern "mysqlclient" fn mysql_commit(m: *MYSQL) callconv(.c) u8;
    extern "mysqlclient" fn mysql_rollback(m: *MYSQL) callconv(.c) u8;
    extern "mysqlclient" fn mysql_select_db(m: *MYSQL, db: [*:0]const u8) callconv(.c) c_int;
    extern "mysqlclient" fn mysql_options(m: *MYSQL, option: c_int, arg: ?*const anyopaque) callconv(.c) c_int;
    // MYSQL_SET_CHARSET_NAME enum value in mysql.h is 7
    const MYSQL_SET_CHARSET_NAME: c_int = 7;
    extern "mysqlclient" fn mysql_character_set_name(m: *MYSQL) callconv(.c) [*:0]const u8;
    extern "mysqlclient" fn mysql_get_client_info() callconv(.c) [*:0]const u8;
    extern "mysqlclient" fn mysql_get_client_version() callconv(.c) c_ulong;
    extern "mysqlclient" fn mysql_get_server_info(m: *MYSQL) callconv(.c) [*:0]const u8;
    extern "mysqlclient" fn mysql_get_server_version(m: *MYSQL) callconv(.c) c_ulong;
    extern "mysqlclient" fn mysql_get_host_info(m: *MYSQL) callconv(.c) [*:0]const u8;
    extern "mysqlclient" fn mysql_thread_id(m: *MYSQL) callconv(.c) c_ulong;
    extern "mysqlclient" fn mysql_ping(m: *MYSQL) callconv(.c) c_int;
};

fn fieldName(field: *mysql.MYSQL_FIELD) [*:0]const u8 {
    // first member of MYSQL_FIELD is `char *name` across libmysqlclient versions
    const ptr: *const [*:0]const u8 = @ptrCast(@alignCast(field));
    return ptr.*;
}

fn getConn(obj: *PhpObject) ?*mysql.MYSQL {
    const v = obj.get("__conn");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn getRes(obj: *PhpObject) ?*mysql.MYSQL_RES {
    const v = obj.get("__res");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

// returns the mysqli object regardless of whether the user passed a
// procedural link arg or invoked a method. for procedural calls `args[0]`
// is the mysqli object; for method calls `$this` lives in the current frame
fn linkObj(ctx: *NativeContext, args: []const Value, idx: usize) ?*PhpObject {
    if (args.len > idx and args[idx] == .object) return args[idx].object;
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn dupZ(ctx: *NativeContext, s: []const u8) ![:0]u8 {
    const buf = try ctx.allocator.allocSentinel(u8, s.len, 0);
    @memcpy(buf[0..s.len], s);
    try ctx.vm.strings.append(ctx.allocator, buf[0 .. s.len + 1]);
    return buf;
}

fn setErrorState(ctx: *NativeContext, obj: *PhpObject, conn: ?*mysql.MYSQL) !void {
    if (conn) |c| {
        const msg_span = std.mem.span(mysql.mysql_error(c));
        const owned = try ctx.allocator.dupe(u8, msg_span);
        try ctx.vm.strings.append(ctx.allocator, owned);
        try obj.set(ctx.allocator, "error", .{ .string = owned });
        try obj.set(ctx.allocator, "errno", .{ .int = @intCast(mysql.mysql_errno(c)) });
    } else {
        try obj.set(ctx.allocator, "error", .{ .string = "" });
        try obj.set(ctx.allocator, "errno", .{ .int = 0 });
    }
}

// ---------- procedural API ----------

fn mysqliInit(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = try ctx.createObject("mysqli");
    if (mysql.mysql_init(null)) |c| {
        try obj.set(ctx.allocator, "__conn", .{ .int = @intCast(@intFromPtr(c)) });
    } else {
        try obj.set(ctx.allocator, "__conn", .{ .int = 0 });
    }
    try obj.set(ctx.allocator, "error", .{ .string = "" });
    try obj.set(ctx.allocator, "errno", .{ .int = 0 });
    try obj.set(ctx.allocator, "__connected", .{ .bool = false });
    return .{ .object = obj };
}

// shared connect path used by mysqli_connect and mysqli::__construct
fn doConnect(ctx: *NativeContext, obj: *PhpObject, host: ?[]const u8, user: ?[]const u8, pass: ?[]const u8, db: ?[]const u8, port: u32, socket: ?[]const u8) !bool {
    const conn = getConn(obj) orelse blk: {
        const c = mysql.mysql_init(null) orelse return false;
        try obj.set(ctx.allocator, "__conn", .{ .int = @intCast(@intFromPtr(c)) });
        break :blk c;
    };

    const host_z = if (host) |h| (try dupZ(ctx, h)).ptr else null;
    const user_z = if (user) |u| (try dupZ(ctx, u)).ptr else null;
    const pass_z = if (pass) |p| (try dupZ(ctx, p)).ptr else null;
    const db_z = if (db) |d| (try dupZ(ctx, d)).ptr else null;
    const sock_z = if (socket) |s| (try dupZ(ctx, s)).ptr else null;

    if (mysql.mysql_real_connect(conn, host_z, user_z, pass_z, db_z, port, sock_z, 0) == null) {
        try setErrorState(ctx, obj, conn);
        return false;
    }
    try obj.set(ctx.allocator, "__connected", .{ .bool = true });
    try setErrorState(ctx, obj, conn);
    // expose the public PHP-visible properties immediately so user code
    // that reads $mysqli->server_info, ->thread_id, ->host_info etc.
    // before issuing any query works
    const server_info = std.mem.span(mysql.mysql_get_server_info(conn));
    const host_info = std.mem.span(mysql.mysql_get_host_info(conn));
    const si_owned = try ctx.allocator.dupe(u8, server_info);
    try ctx.vm.strings.append(ctx.allocator, si_owned);
    const hi_owned = try ctx.allocator.dupe(u8, host_info);
    try ctx.vm.strings.append(ctx.allocator, hi_owned);
    try obj.set(ctx.allocator, "server_info", .{ .string = si_owned });
    try obj.set(ctx.allocator, "host_info", .{ .string = hi_owned });
    try obj.set(ctx.allocator, "server_version", .{ .int = @intCast(mysql.mysql_get_server_version(conn)) });
    try obj.set(ctx.allocator, "thread_id", .{ .int = @intCast(mysql.mysql_thread_id(conn)) });
    try obj.set(ctx.allocator, "client_version", .{ .int = @intCast(mysql.mysql_get_client_version()) });
    return true;
}

fn argOptString(args: []const Value, idx: usize) ?[]const u8 {
    if (args.len <= idx) return null;
    return switch (args[idx]) {
        .string => |s| s,
        .null => null,
        else => null,
    };
}

fn argOptInt(args: []const Value, idx: usize, default: i64) i64 {
    if (args.len <= idx) return default;
    return switch (args[idx]) {
        .int => |i| i,
        .null => default,
        else => default,
    };
}

fn mysqliConnect(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = try ctx.createObject("mysqli");
    try obj.set(ctx.allocator, "error", .{ .string = "" });
    try obj.set(ctx.allocator, "errno", .{ .int = 0 });
    try obj.set(ctx.allocator, "__connected", .{ .bool = false });

    const host = argOptString(args, 0);
    const user = argOptString(args, 1);
    const pass = argOptString(args, 2);
    const db = argOptString(args, 3);
    const port: u32 = @intCast(argOptInt(args, 4, 3306));
    const socket = argOptString(args, 5);

    const ok = try doConnect(ctx, obj, host, user, pass, db, port, socket);
    if (!ok) return .{ .bool = false };
    return .{ .object = obj };
}

fn mysqliRealConnect(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // procedural variant takes the link as arg 0; the method form puts the
    // link in $this. linkObj resolves both
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    const offset: usize = if (args.len > 0 and args[0] == .object) 1 else 0;
    const host = argOptString(args, offset + 0);
    const user = argOptString(args, offset + 1);
    const pass = argOptString(args, offset + 2);
    const db = argOptString(args, offset + 3);
    const port: u32 = @intCast(argOptInt(args, offset + 4, 3306));
    const socket = argOptString(args, offset + 5);
    return .{ .bool = try doConnect(ctx, link, host, user, pass, db, port, socket) };
}

fn mysqliClose(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    if (getConn(link)) |c| {
        // mysql_close is safe to call on a handle returned by mysql_init even
        // when never connected — releases the allocated handle either way
        mysql.mysql_close(c);
        try link.set(ctx.allocator, "__conn", .{ .int = 0 });
        try link.set(ctx.allocator, "__connected", .{ .bool = false });
    }
    return .{ .bool = true };
}

fn mysqliQuery(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    const conn = getConn(link) orelse return .{ .bool = false };
    if (!isConnected(link)) return .{ .bool = false };
    // determine which arg holds the SQL
    const sql_arg: Value = if (args.len > 0 and args[0] == .object) (if (args.len > 1) args[1] else .null) else if (args.len > 0) args[0] else .null;
    if (sql_arg != .string) return .{ .bool = false };
    const sql = sql_arg.string;
    if (mysql.mysql_real_query(conn, sql.ptr, @intCast(sql.len)) != 0) {
        try setErrorState(ctx, link, conn);
        return .{ .bool = false };
    }
    try setErrorState(ctx, link, conn);
    // expose state PHP makes available as object properties on the mysqli link.
    // mysql_affected_rows returns (my_ulonglong)-1 (== UINT64_MAX) when no rows
    // were affected by the most recent query (e.g. SELECT); reflect that as -1
    const ar_raw = mysql.mysql_affected_rows(conn);
    const ar: i64 = if (ar_raw == std.math.maxInt(u64)) -1 else @intCast(ar_raw);
    try link.set(ctx.allocator, "affected_rows", .{ .int = ar });
    try link.set(ctx.allocator, "insert_id", .{ .int = @intCast(mysql.mysql_insert_id(conn)) });
    // not all queries return a result set; for INSERT/UPDATE/DELETE return true
    const res_opt = mysql.mysql_store_result(conn);
    const res = res_opt orelse return .{ .bool = true };

    const result_obj = try ctx.createObject("mysqli_result");
    try result_obj.set(ctx.allocator, "__res", .{ .int = @intCast(@intFromPtr(res)) });
    try result_obj.set(ctx.allocator, "num_rows", .{ .int = @intCast(mysql.mysql_num_rows(res)) });
    const nf: i64 = @intCast(mysql.mysql_num_fields(res));
    try result_obj.set(ctx.allocator, "num_fields", .{ .int = nf });
    // mysqli_result exposes the column count as `field_count` in PHP. keep
    // both spellings populated so user code that reaches for either works
    try result_obj.set(ctx.allocator, "field_count", .{ .int = nf });
    return .{ .object = result_obj };
}

// row fetch shared between fetch_array / fetch_assoc / fetch_row
// flags: 1 = assoc, 2 = numeric, 3 = both
fn fetchRow(ctx: *NativeContext, result_obj: *PhpObject, flags: u8) !Value {
    const res = getRes(result_obj) orelse return .null;
    const row = mysql.mysql_fetch_row(res) orelse return .null;
    const num: usize = mysql.mysql_num_fields(res);
    const lens = mysql.mysql_fetch_lengths(res);
    const arr = try ctx.createArray();
    _ = mysql.mysql_field_seek(res, 0);
    var i: usize = 0;
    while (i < num) : (i += 1) {
        const cell: Value = blk: {
            const p_opt = row[i];
            if (p_opt == null) break :blk .null;
            const p: [*:0]const u8 = p_opt.?;
            const len: usize = if (lens) |l| @intCast(l[i]) else std.mem.len(p);
            const owned = try ctx.allocator.dupe(u8, p[0..len]);
            try ctx.vm.strings.append(ctx.allocator, owned);
            break :blk Value{ .string = owned };
        };
        if (flags & 2 != 0) try arr.set(ctx.allocator, .{ .int = @intCast(i) }, cell);
        if (flags & 1 != 0) {
            const field = mysql.mysql_fetch_field(res) orelse continue;
            const fname_ptr = fieldName(field);
            const fname = std.mem.span(fname_ptr);
            const owned_name = try ctx.allocator.dupe(u8, fname);
            try ctx.vm.strings.append(ctx.allocator, owned_name);
            try arr.set(ctx.allocator, .{ .string = owned_name }, cell);
        } else {
            _ = mysql.mysql_fetch_field(res);
        }
    }
    return .{ .array = arr };
}

fn mysqliFetchAssoc(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const result_obj = linkObj(ctx, args, 0) orelse return .null;
    return try fetchRow(ctx, result_obj, 1);
}

fn mysqliFetchArray(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const result_obj = linkObj(ctx, args, 0) orelse return .null;
    // procedural form has optional mode at args[1]; method form at args[0]
    const mode_arg: i64 = if (args.len > 0 and args[0] == .object) argOptInt(args, 1, 3) else argOptInt(args, 0, 3);
    const flags: u8 = @intCast(@as(u64, @bitCast(mode_arg)) & 3);
    return try fetchRow(ctx, result_obj, if (flags == 0) 3 else flags);
}

fn mysqliFetchRow(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const result_obj = linkObj(ctx, args, 0) orelse return .null;
    return try fetchRow(ctx, result_obj, 2);
}

fn mysqliFetchAll(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const result_obj = linkObj(ctx, args, 0) orelse return .{ .array = try ctx.createArray() };
    const mode_arg: i64 = if (args.len > 0 and args[0] == .object) argOptInt(args, 1, 2) else argOptInt(args, 0, 2);
    const flags: u8 = @intCast(@as(u64, @bitCast(mode_arg)) & 3);
    const eff: u8 = if (flags == 0) 2 else flags;
    const out = try ctx.createArray();
    while (true) {
        const row = try fetchRow(ctx, result_obj, eff);
        if (row == .null) break;
        try out.append(ctx.allocator, row);
    }
    return .{ .array = out };
}

fn mysqliNumRows(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const result_obj = linkObj(ctx, args, 0) orelse return .{ .int = 0 };
    const v = result_obj.get("num_rows");
    return if (v == .int) v else .{ .int = 0 };
}

fn mysqliAffectedRows(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .int = 0 };
    const c = getConn(link) orelse return .{ .int = 0 };
    if (!isConnected(link)) return .{ .int = 0 };
    const raw = mysql.mysql_affected_rows(c);
    return .{ .int = if (raw == std.math.maxInt(u64)) -1 else @intCast(raw) };
}

fn mysqliInsertId(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .int = 0 };
    const c = getConn(link) orelse return .{ .int = 0 };
    if (!isConnected(link)) return .{ .int = 0 };
    return .{ .int = @intCast(mysql.mysql_insert_id(c)) };
}

fn mysqliError(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .string = "" };
    return link.get("error");
}

fn mysqliErrno(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .int = 0 };
    return link.get("errno");
}

fn mysqliConnectError(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    _ = ctx;
    return .null;
}

fn mysqliConnectErrno(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

fn mysqliRealEscapeString(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .string = "" };
    const str_arg: Value = if (args.len > 0 and args[0] == .object) (if (args.len > 1) args[1] else .null) else if (args.len > 0) args[0] else .null;
    if (str_arg != .string) return .{ .string = "" };
    const conn = getConn(link) orelse return try fallbackEscape(ctx, str_arg.string);
    if (!isConnected(link)) return try fallbackEscape(ctx, str_arg.string);
    const src = str_arg.string;
    const buf = try ctx.allocator.alloc(u8, src.len * 2 + 1);
    const written = mysql.mysql_real_escape_string(conn, buf.ptr, src.ptr, @intCast(src.len));
    const out = buf[0..@intCast(written)];
    const owned = try ctx.allocator.dupe(u8, out);
    ctx.allocator.free(buf);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn fallbackEscape(ctx: *NativeContext, src: []const u8) !Value {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(ctx.allocator);
    for (src) |c| {
        switch (c) {
            0, '\n', '\r', '\\', '\'', '"', 0x1a => {
                try buf.append(ctx.allocator, '\\');
                try buf.append(ctx.allocator, switch (c) {
                    0 => '0',
                    '\n' => 'n',
                    '\r' => 'r',
                    0x1a => 'Z',
                    else => c,
                });
            },
            else => try buf.append(ctx.allocator, c),
        }
    }
    const owned = try ctx.allocator.dupe(u8, buf.items);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn mysqliSelectDb(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    const conn = getConn(link) orelse return .{ .bool = false };
    if (!isConnected(link)) return .{ .bool = false };
    const db_arg: Value = if (args.len > 0 and args[0] == .object) (if (args.len > 1) args[1] else .null) else if (args.len > 0) args[0] else .null;
    if (db_arg != .string) return .{ .bool = false };
    const db_z = try dupZ(ctx, db_arg.string);
    const rc = mysql.mysql_select_db(conn, db_z.ptr);
    if (rc != 0) {
        try setErrorState(ctx, link, conn);
        return .{ .bool = false };
    }
    return .{ .bool = true };
}

fn mysqliSetCharset(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    const conn = getConn(link) orelse return .{ .bool = false };
    if (!isConnected(link)) return .{ .bool = false };
    const cs_arg: Value = if (args.len > 0 and args[0] == .object) (if (args.len > 1) args[1] else .null) else if (args.len > 0) args[0] else .null;
    if (cs_arg != .string) return .{ .bool = false };
    const cs_z = try dupZ(ctx, cs_arg.string);
    // mysql_set_charset was removed in libmysqlclient 8.x. mysql_options
    // with MYSQL_SET_CHARSET_NAME is the supported equivalent; it accepts a
    // C string pointer (cast through anyopaque)
    return .{ .bool = mysql.mysql_options(conn, mysql.MYSQL_SET_CHARSET_NAME, @ptrCast(cs_z.ptr)) == 0 };
}

fn mysqliCharacterSetName(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .string = "" };
    const conn = getConn(link) orelse return .{ .string = "" };
    if (!isConnected(link)) return .{ .string = "" };
    const name = std.mem.span(mysql.mysql_character_set_name(conn));
    const owned = try ctx.allocator.dupe(u8, name);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn mysqliGetClientInfo(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const info = std.mem.span(mysql.mysql_get_client_info());
    const owned = try ctx.allocator.dupe(u8, info);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn mysqliGetClientVersion(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = @intCast(mysql.mysql_get_client_version()) };
}

fn isConnected(link: *PhpObject) bool {
    const v = link.get("__connected");
    return v == .bool and v.bool;
}

fn mysqliGetServerInfo(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .string = "" };
    const conn = getConn(link) orelse return .{ .string = "" };
    if (!isConnected(link)) return .{ .string = "" };
    const info = std.mem.span(mysql.mysql_get_server_info(conn));
    const owned = try ctx.allocator.dupe(u8, info);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn mysqliGetServerVersion(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .int = 0 };
    const conn = getConn(link) orelse return .{ .int = 0 };
    if (!isConnected(link)) return .{ .int = 0 };
    return .{ .int = @intCast(mysql.mysql_get_server_version(conn)) };
}

fn mysqliGetHostInfo(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .string = "" };
    const conn = getConn(link) orelse return .{ .string = "" };
    if (!isConnected(link)) return .{ .string = "" };
    const info = std.mem.span(mysql.mysql_get_host_info(conn));
    const owned = try ctx.allocator.dupe(u8, info);
    try ctx.vm.strings.append(ctx.allocator, owned);
    return .{ .string = owned };
}

fn mysqliThreadId(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .int = 0 };
    const conn = getConn(link) orelse return .{ .int = 0 };
    if (!isConnected(link)) return .{ .int = 0 };
    return .{ .int = @intCast(mysql.mysql_thread_id(conn)) };
}

fn mysqliPing(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    const conn = getConn(link) orelse return .{ .bool = false };
    if (!isConnected(link)) return .{ .bool = false };
    return .{ .bool = mysql.mysql_ping(conn) == 0 };
}

fn mysqliAutocommit(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    const conn = getConn(link) orelse return .{ .bool = false };
    if (!isConnected(link)) return .{ .bool = false };
    const mode_arg: Value = if (args.len > 0 and args[0] == .object) (if (args.len > 1) args[1] else .{ .bool = true }) else if (args.len > 0) args[0] else .{ .bool = true };
    const mode: u8 = if (mode_arg.isTruthy()) 1 else 0;
    return .{ .bool = mysql.mysql_autocommit(conn, mode) == 0 };
}

fn mysqliCommit(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    const conn = getConn(link) orelse return .{ .bool = false };
    if (!isConnected(link)) return .{ .bool = false };
    return .{ .bool = mysql.mysql_commit(conn) == 0 };
}

fn mysqliRollback(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const link = linkObj(ctx, args, 0) orelse return .{ .bool = false };
    const conn = getConn(link) orelse return .{ .bool = false };
    if (!isConnected(link)) return .{ .bool = false };
    return .{ .bool = mysql.mysql_rollback(conn) == 0 };
}

fn mysqliFreeResult(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const result_obj = linkObj(ctx, args, 0) orelse return .null;
    if (getRes(result_obj)) |r| {
        mysql.mysql_free_result(r);
        try result_obj.set(ctx.allocator, "__res", .{ .int = 0 });
    }
    return .null;
}

fn mysqliFieldCount(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    // proc form: mysqli_field_count(link). method form: $result->field_count
    const obj = linkObj(ctx, args, 0) orelse return .{ .int = 0 };
    if (std.mem.eql(u8, obj.class_name, "mysqli_result")) {
        const v = obj.get("num_fields");
        return if (v == .int) v else .{ .int = 0 };
    }
    return .{ .int = 0 };
}

fn mysqliNumFields(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = linkObj(ctx, args, 0) orelse return .{ .int = 0 };
    const v = obj.get("num_fields");
    return if (v == .int) v else .{ .int = 0 };
}

fn mysqliReport(_: *NativeContext, _: []const Value) RuntimeError!Value {
    // we don't emit warning streams driven by mysql_report() so accepting the
    // call as a no-op is correct: a real run with REPORT_ERROR would have
    // raised PHP warnings on every libmysql error, but we already surface
    // errors via mysqli_error / errno
    return .{ .bool = true };
}

// ---------- class constructor ----------

fn mysqliConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return .null;
    if (v != .object) return .null;
    const obj = v.object;
    try obj.set(ctx.allocator, "error", .{ .string = "" });
    try obj.set(ctx.allocator, "errno", .{ .int = 0 });
    try obj.set(ctx.allocator, "__connected", .{ .bool = false });

    const c = mysql.mysql_init(null) orelse return .null;
    try obj.set(ctx.allocator, "__conn", .{ .int = @intCast(@intFromPtr(c)) });

    // when called with no args, leave the handle uninitialized (mirrors mysqli_init)
    if (args.len == 0) return .null;

    const host = argOptString(args, 0);
    const user = argOptString(args, 1);
    const pass = argOptString(args, 2);
    const db = argOptString(args, 3);
    const port: u32 = @intCast(argOptInt(args, 4, 3306));
    const socket = argOptString(args, 5);
    _ = try doConnect(ctx, obj, host, user, pass, db, port, socket);
    return .null;
}

// ---------- registration ----------

pub const entries = .{
    .{ "mysqli_init", mysqliInit },
    .{ "mysqli_connect", mysqliConnect },
    .{ "mysqli_real_connect", mysqliRealConnect },
    .{ "mysqli_close", mysqliClose },
    .{ "mysqli_query", mysqliQuery },
    .{ "mysqli_fetch_assoc", mysqliFetchAssoc },
    .{ "mysqli_fetch_array", mysqliFetchArray },
    .{ "mysqli_fetch_row", mysqliFetchRow },
    .{ "mysqli_fetch_all", mysqliFetchAll },
    .{ "mysqli_num_rows", mysqliNumRows },
    .{ "mysqli_affected_rows", mysqliAffectedRows },
    .{ "mysqli_insert_id", mysqliInsertId },
    .{ "mysqli_error", mysqliError },
    .{ "mysqli_errno", mysqliErrno },
    .{ "mysqli_connect_error", mysqliConnectError },
    .{ "mysqli_connect_errno", mysqliConnectErrno },
    .{ "mysqli_real_escape_string", mysqliRealEscapeString },
    .{ "mysqli_escape_string", mysqliRealEscapeString },
    .{ "mysqli_select_db", mysqliSelectDb },
    .{ "mysqli_set_charset", mysqliSetCharset },
    .{ "mysqli_character_set_name", mysqliCharacterSetName },
    .{ "mysqli_get_client_info", mysqliGetClientInfo },
    .{ "mysqli_get_client_version", mysqliGetClientVersion },
    .{ "mysqli_get_server_info", mysqliGetServerInfo },
    .{ "mysqli_get_server_version", mysqliGetServerVersion },
    .{ "mysqli_get_host_info", mysqliGetHostInfo },
    .{ "mysqli_thread_id", mysqliThreadId },
    .{ "mysqli_ping", mysqliPing },
    .{ "mysqli_autocommit", mysqliAutocommit },
    .{ "mysqli_begin_transaction", mysqliAutocommit },
    .{ "mysqli_commit", mysqliCommit },
    .{ "mysqli_rollback", mysqliRollback },
    .{ "mysqli_free_result", mysqliFreeResult },
    .{ "mysqli_field_count", mysqliFieldCount },
    .{ "mysqli_num_fields", mysqliNumFields },
    .{ "mysqli_report", mysqliReport },
};

pub fn register(vm: *VM, a: Allocator) !void {
    var mc = ClassDef{ .name = "mysqli" };
    inline for (.{
        .{ "__construct", 6 },        .{ "connect", 6 },         .{ "real_connect", 6 },
        .{ "close", 0 },              .{ "query", 1 },           .{ "real_query", 1 },
        .{ "select_db", 1 },          .{ "set_charset", 1 },     .{ "character_set_name", 0 },
        .{ "real_escape_string", 1 }, .{ "escape_string", 1 },
        .{ "get_server_info", 0 },    .{ "get_server_version", 0 },
        .{ "get_host_info", 0 },      .{ "get_client_info", 0 },
        .{ "thread_id", 0 },          .{ "ping", 0 },
        .{ "autocommit", 1 },         .{ "begin_transaction", 0 },
        .{ "commit", 0 },             .{ "rollback", 0 },
        .{ "prepare", 1 },            .{ "stat", 0 },
    }) |m| {
        try mc.methods.put(a, m[0], .{ .name = m[0], .arity = m[1] });
    }
    try vm.classes.put(a, "mysqli", mc);
    try vm.native_fns.put(a, "mysqli::__construct", mysqliConstruct);
    try vm.native_fns.put(a, "mysqli::connect", mysqliRealConnect);
    try vm.native_fns.put(a, "mysqli::real_connect", mysqliRealConnect);
    try vm.native_fns.put(a, "mysqli::close", mysqliClose);
    try vm.native_fns.put(a, "mysqli::query", mysqliQuery);
    try vm.native_fns.put(a, "mysqli::real_query", mysqliQuery);
    try vm.native_fns.put(a, "mysqli::select_db", mysqliSelectDb);
    try vm.native_fns.put(a, "mysqli::set_charset", mysqliSetCharset);
    try vm.native_fns.put(a, "mysqli::character_set_name", mysqliCharacterSetName);
    try vm.native_fns.put(a, "mysqli::real_escape_string", mysqliRealEscapeString);
    try vm.native_fns.put(a, "mysqli::escape_string", mysqliRealEscapeString);
    try vm.native_fns.put(a, "mysqli::get_server_info", mysqliGetServerInfo);
    try vm.native_fns.put(a, "mysqli::get_server_version", mysqliGetServerVersion);
    try vm.native_fns.put(a, "mysqli::get_host_info", mysqliGetHostInfo);
    try vm.native_fns.put(a, "mysqli::get_client_info", mysqliGetClientInfo);
    try vm.native_fns.put(a, "mysqli::thread_id", mysqliThreadId);
    try vm.native_fns.put(a, "mysqli::ping", mysqliPing);
    try vm.native_fns.put(a, "mysqli::autocommit", mysqliAutocommit);
    try vm.native_fns.put(a, "mysqli::begin_transaction", mysqliAutocommit);
    try vm.native_fns.put(a, "mysqli::commit", mysqliCommit);
    try vm.native_fns.put(a, "mysqli::rollback", mysqliRollback);

    var rc = ClassDef{ .name = "mysqli_result" };
    inline for (.{
        .{ "fetch_assoc", 0 }, .{ "fetch_array", 1 }, .{ "fetch_row", 0 }, .{ "fetch_all", 1 },
        .{ "fetch_object", 2 }, .{ "free", 0 }, .{ "close", 0 }, .{ "data_seek", 1 },
        .{ "num_rows", 0 }, .{ "field_count", 0 },
    }) |m| {
        try rc.methods.put(a, m[0], .{ .name = m[0], .arity = m[1] });
    }
    try vm.classes.put(a, "mysqli_result", rc);
    try vm.native_fns.put(a, "mysqli_result::fetch_assoc", mysqliFetchAssoc);
    try vm.native_fns.put(a, "mysqli_result::fetch_array", mysqliFetchArray);
    try vm.native_fns.put(a, "mysqli_result::fetch_row", mysqliFetchRow);
    try vm.native_fns.put(a, "mysqli_result::fetch_all", mysqliFetchAll);
    try vm.native_fns.put(a, "mysqli_result::free", mysqliFreeResult);
    try vm.native_fns.put(a, "mysqli_result::close", mysqliFreeResult);

    var sc = ClassDef{ .name = "mysqli_stmt" };
    try sc.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try vm.classes.put(a, "mysqli_stmt", sc);

    try vm.classes.put(a, "mysqli_driver", ClassDef{ .name = "mysqli_driver" });
    try vm.classes.put(a, "mysqli_warning", ClassDef{ .name = "mysqli_warning" });
    try vm.classes.put(a, "mysqli_sql_exception", ClassDef{ .name = "mysqli_sql_exception", .parent = "RuntimeException" });
}

pub fn cleanupConnections(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "mysqli_result")) {
            if (getRes(obj)) |r| mysql.mysql_free_result(r);
        }
    }
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "mysqli")) {
            if (getConn(obj)) |c| mysql.mysql_close(c);
        }
    }
}
