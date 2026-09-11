const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeHandle = @import("../runtime/value.zig").NativeHandle;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const pdo = @import("pdo.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;

const mysql = struct {
    const MYSQL = opaque {};
    const MYSQL_RES = opaque {};
    // MYSQL_FIELD struct layout varies across platforms/versions
    // only access the name pointer at offset 0 which is stable
    const MYSQL_FIELD = opaque {};

    extern "c" fn mysql_init(m: ?*MYSQL) callconv(.c) ?*MYSQL;
    extern "c" fn mysql_real_connect(m: *MYSQL, host: ?[*:0]const u8, user: ?[*:0]const u8, passwd: ?[*:0]const u8, db: ?[*:0]const u8, port: c_uint, socket: ?[*:0]const u8, flags: c_ulong) callconv(.c) ?*MYSQL;
    extern "c" fn mysql_close(m: *MYSQL) callconv(.c) void;
    extern "c" fn mysql_error(m: *MYSQL) callconv(.c) [*:0]const u8;
    extern "c" fn mysql_real_query(m: *MYSQL, q: [*]const u8, len: c_ulong) callconv(.c) c_int;
    extern "c" fn mysql_store_result(m: *MYSQL) callconv(.c) ?*MYSQL_RES;
    extern "c" fn mysql_affected_rows(m: *MYSQL) callconv(.c) u64;
    extern "c" fn mysql_insert_id(m: *MYSQL) callconv(.c) u64;
    extern "c" fn mysql_num_fields(res: *MYSQL_RES) callconv(.c) c_uint;
    extern "c" fn mysql_field_seek(res: *MYSQL_RES, offset: c_uint) callconv(.c) c_uint;
    extern "c" fn mysql_fetch_field(res: *MYSQL_RES) callconv(.c) ?*MYSQL_FIELD;
    extern "c" fn mysql_fetch_row(res: *MYSQL_RES) callconv(.c) ?[*]?[*:0]const u8;
    extern "c" fn mysql_fetch_lengths(res: *MYSQL_RES) callconv(.c) ?[*]c_ulong;
    extern "c" fn mysql_free_result(res: *MYSQL_RES) callconv(.c) void;
    extern "c" fn mysql_num_rows(res: *MYSQL_RES) callconv(.c) u64;
    extern "c" fn mysql_real_escape_string(m: *MYSQL, to: [*]u8, from: [*]const u8, length: c_ulong) callconv(.c) c_ulong;
    extern "c" fn mysql_autocommit(m: *MYSQL, auto_mode: u8) callconv(.c) u8;
    extern "c" fn mysql_commit(m: *MYSQL) callconv(.c) u8;
    extern "c" fn mysql_rollback(m: *MYSQL) callconv(.c) u8;
};

fn fieldName(field: *mysql.MYSQL_FIELD) [*:0]const u8 {
    // name is the first member of MYSQL_FIELD on all platforms (char*)
    const ptr: *const [*:0]const u8 = @ptrCast(@alignCast(field));
    return ptr.*;
}

fn getConn(obj: *PhpObject) ?*mysql.MYSQL {
    return obj.native.get(mysql.MYSQL, .pdo_mysql) orelse obj.native.getAux(mysql.MYSQL, .pdo_mysql_stmt);
}

fn getRes(obj: *PhpObject) ?*mysql.MYSQL_RES {
    return obj.native.get(mysql.MYSQL_RES, .pdo_mysql_stmt);
}

fn attachConn(obj: *PhpObject, conn: *mysql.MYSQL) void {
    obj.native = .{ .kind = .pdo_mysql, .ptr = @intFromPtr(conn) };
}

fn attachStmt(obj: *PhpObject, conn: *mysql.MYSQL, res: ?*mysql.MYSQL_RES) void {
    obj.native = .{ .kind = .pdo_mysql_stmt, .ptr = NativeHandle.addr(res), .aux = @intFromPtr(conn) };
}

fn setRes(obj: *PhpObject, res: ?*mysql.MYSQL_RES) void {
    obj.native.ptr = NativeHandle.addr(res);
}

fn parseDsnParams(rest: []const u8) struct { host: ?[]const u8, port: u16, dbname: ?[]const u8, unix_socket: ?[]const u8 } {
    var host: ?[]const u8 = null;
    var port: u16 = 3306;
    var dbname: ?[]const u8 = null;
    var unix_socket: ?[]const u8 = null;

    var iter = std.mem.splitScalar(u8, rest, ';');
    while (iter.next()) |param| {
        if (std.mem.indexOf(u8, param, "=")) |eq| {
            const key = std.mem.trim(u8, param[0..eq], " ");
            const val = std.mem.trim(u8, param[eq + 1 ..], " ");
            if (std.mem.eql(u8, key, "host")) host = val;
            if (std.mem.eql(u8, key, "port")) port = std.fmt.parseInt(u16, val, 10) catch 3306;
            if (std.mem.eql(u8, key, "dbname")) dbname = val;
            if (std.mem.eql(u8, key, "unix_socket")) unix_socket = val;
        }
    }
    return .{ .host = host, .port = port, .dbname = dbname, .unix_socket = unix_socket };
}

pub fn connect(ctx: *NativeContext, obj: *PhpObject, rest: []const u8, args: []const Value) RuntimeError!NativeResult {
    const params = parseDsnParams(rest);
    const user = if (args.len >= 2 and args[1] == .string) args[1].string.bytes() else null;
    const pass = if (args.len >= 3 and args[2] == .string) args[2].string.bytes() else null;

    const conn = mysql.mysql_init(null) orelse return pdo.throwPdo(ctx, "Failed to initialize MySQL connection");

    const host_z: ?[*:0]const u8 = if (params.host) |h| (try pdo.dupeZ(ctx, h)).ptr else null;
    const user_z: ?[*:0]const u8 = if (user) |u| (try pdo.dupeZ(ctx, u)).ptr else null;
    const pass_z: ?[*:0]const u8 = if (pass) |p| (try pdo.dupeZ(ctx, p)).ptr else null;
    const db_z: ?[*:0]const u8 = if (params.dbname) |d| (try pdo.dupeZ(ctx, d)).ptr else null;
    const sock_z: ?[*:0]const u8 = if (params.unix_socket) |s| (try pdo.dupeZ(ctx, s)).ptr else null;

    if (mysql.mysql_real_connect(conn, host_z, user_z, pass_z, db_z, params.port, sock_z, 0) == null) {
        const msg = try ctx.createString(std.mem.span(mysql.mysql_error(conn)));
        mysql.mysql_close(conn);
        return pdo.throwPdo(ctx, msg);
    }

    attachConn(obj, conn);
    return NativeResult.scalar(.null);
}

pub fn exec(ctx: *NativeContext, obj: *PhpObject, sql: []const u8) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return pdo.throwPdo(ctx, "Database not connected");
    if (mysql.mysql_real_query(conn, sql.ptr, @intCast(sql.len)) != 0) {
        return pdo.throwPdo(ctx, std.mem.span(mysql.mysql_error(conn)));
    }
    // consume result if any (for non-SELECT)
    if (mysql.mysql_store_result(conn)) |res| mysql.mysql_free_result(res);
    return NativeResult.scalar(.{ .int = @intCast(mysql.mysql_affected_rows(conn)) });
}

pub fn query(ctx: *NativeContext, obj: *PhpObject, sql: []const u8) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return pdo.throwPdo(ctx, "Database not connected");
    if (mysql.mysql_real_query(conn, sql.ptr, @intCast(sql.len)) != 0) {
        return pdo.throwPdo(ctx, std.mem.span(mysql.mysql_error(conn)));
    }
    const res = mysql.mysql_store_result(conn) orelse return pdo.throwPdo(ctx, std.mem.span(mysql.mysql_error(conn)));

    const stmt_obj = try ctx.createObject("PDOStatement");
    attachStmt(stmt_obj, conn, res);
    try stmt_obj.set(ctx.allocator, "__current_row", .{ .int = 0 });
    try stmt_obj.set(ctx.allocator, "__has_row", .{ .bool = true });
    try stmt_obj.set(ctx.allocator, "__stepped", .{ .bool = true });
    return NativeResult.borrowed(.{ .object = stmt_obj });
}

pub fn prepare(ctx: *NativeContext, obj: *PhpObject, sql: []const u8) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return pdo.throwPdo(ctx, "Database not connected");

    // rewrite named params to positional ? and build param map
    var rewritten = std.ArrayListUnmanaged(u8){};
    var param_names = std.ArrayListUnmanaged([]const u8){};
    var i: usize = 0;
    var in_string = false;
    while (i < sql.len) {
        if (sql[i] == '\'' and !in_string) {
            in_string = true;
            try rewritten.append(ctx.allocator, sql[i]);
            i += 1;
        } else if (sql[i] == '\'' and in_string) {
            in_string = false;
            try rewritten.append(ctx.allocator, sql[i]);
            i += 1;
        } else if (!in_string and sql[i] == ':' and i + 1 < sql.len and std.ascii.isAlphabetic(sql[i + 1])) {
            const start = i + 1;
            i += 1;
            while (i < sql.len and (std.ascii.isAlphanumeric(sql[i]) or sql[i] == '_')) i += 1;
            try param_names.append(ctx.allocator, sql[start..i]);
            try rewritten.append(ctx.allocator, '?');
        } else {
            try rewritten.append(ctx.allocator, sql[i]);
            i += 1;
        }
    }

    const stmt_obj = try ctx.createObject("PDOStatement");
    attachStmt(stmt_obj, conn, null);
    try stmt_obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    try stmt_obj.set(ctx.allocator, "__stepped", .{ .bool = false });

    const sql_owned = try rewritten.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, sql_owned);
    try stmt_obj.set(ctx.allocator, "__sql", .{ .string = Value.String.borrowed(sql_owned) });

    if (param_names.items.len > 0) {
        var map = try ctx.createArray();
        for (param_names.items, 0..) |name, idx| {
            try map.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, .{ .int = @intCast(idx) });
        }
        try stmt_obj.set(ctx.allocator, "__param_map", .{ .array = map });
    }
    param_names.deinit(ctx.allocator);

    return NativeResult.borrowed(.{ .object = stmt_obj });
}

pub fn stmtExecute(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const sql_val = obj.get("__sql");
    if (sql_val != .string) return NativeResult.scalar(.{ .bool = false });
    var sql = sql_val.string.bytes();

    // if params provided, escape and interpolate
    if (args.len >= 1 and args[0] == .array) {
        const params = args[0].array;
        const param_map_val = obj.get("__param_map");
        sql = try interpolateParams(ctx, conn, sql, params, if (param_map_val == .array) param_map_val.array else null);
    }

    // free previous result if any
    if (getRes(obj)) |old_res| {
        mysql.mysql_free_result(old_res);
        setRes(obj, null);
    }

    if (mysql.mysql_real_query(conn, sql.ptr, @intCast(sql.len)) != 0) {
        return pdo.throwPdo(ctx, std.mem.span(mysql.mysql_error(conn)));
    }

    if (mysql.mysql_store_result(conn)) |res| {
        setRes(obj, res);
        try obj.set(ctx.allocator, "__current_row", .{ .int = 0 });
        try obj.set(ctx.allocator, "__has_row", .{ .bool = true });
    } else {
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    }
    try obj.set(ctx.allocator, "__stepped", .{ .bool = true });
    try obj.set(ctx.allocator, "__row_count", .{ .int = @intCast(mysql.mysql_affected_rows(conn)) });

    return NativeResult.scalar(.{ .bool = true });
}

fn interpolateParams(ctx: *NativeContext, conn: *mysql.MYSQL, sql: []const u8, params: *PhpArray, param_map: ?*PhpArray) ![]const u8 {
    // collect param values in positional order
    var positional = std.ArrayListUnmanaged([]const u8){};
    defer positional.deinit(ctx.allocator);

    if (param_map) |pm| {
        // named params - resolve to positional
        var max_idx: usize = 0;
        for (pm.entries.items) |entry| {
            if (entry.value == .int) {
                const idx: usize = @intCast(entry.value.int);
                if (idx >= max_idx) max_idx = idx + 1;
            }
        }
        try positional.resize(ctx.allocator, max_idx);
        @memset(positional.items, "");
        for (params.entries.items) |entry| {
            var name = if (entry.key == .string) entry.key.string.bytes() else "";
            if (name.len > 0 and name[0] == ':') name = name[1..];
            const idx_val = pm.get(.{ .string = Value.String.borrowed(name) });
            if (idx_val == .int) {
                const idx: usize = @intCast(idx_val.int);
                positional.items[idx] = try valueToSqlString(ctx, conn, entry.value);
            }
        }
    } else {
        // positional params
        for (params.entries.items) |entry| {
            try positional.append(ctx.allocator, try valueToSqlString(ctx, conn, entry.value));
        }
    }

    // replace ? placeholders with escaped values
    var result = std.ArrayListUnmanaged(u8){};
    var param_idx: usize = 0;
    for (sql) |c| {
        if (c == '?' and param_idx < positional.items.len) {
            try result.appendSlice(ctx.allocator, positional.items[param_idx]);
            param_idx += 1;
        } else {
            try result.append(ctx.allocator, c);
        }
    }
    const owned = try result.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, owned);
    return owned;
}

fn valueToSqlString(ctx: *NativeContext, conn: *mysql.MYSQL, val: Value) ![]const u8 {
    switch (val) {
        .null => return "NULL",
        .bool => |b| return if (b) "1" else "0",
        .int => |i| {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return "0";
            return try ctx.createString(s);
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return "0";
            return try ctx.createString(s);
        },
        .string => |php_s| {
            // escape and quote
            const s = php_s.bytes();
            const escaped = try ctx.allocator.alloc(u8, s.len * 2 + 3);
            escaped[0] = '\'';
            const elen = mysql.mysql_real_escape_string(conn, escaped[1..].ptr, s.ptr, @intCast(s.len));
            escaped[1 + elen] = '\'';
            escaped[2 + elen] = 0;
            const result = escaped[0 .. 2 + elen];
            try ctx.strings.append(ctx.allocator, escaped);
            return result;
        },
        else => return "NULL",
    }
}

pub fn stmtFetch(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!NativeResult {
    const res = getRes(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const row_ptrs = mysql.mysql_fetch_row(res) orelse return NativeResult.scalar(.{ .bool = false });
    const lengths = mysql.mysql_fetch_lengths(res) orelse return NativeResult.scalar(.{ .bool = false });
    const num_fields = mysql.mysql_num_fields(res);

    const mode: i64 = if (args.len >= 1 and args[0] == .int) args[0].int else 4;
    var row = try ctx.createArray();

    // collect field names if needed for FETCH_ASSOC or FETCH_BOTH
    var field_names: [64][]const u8 = undefined;
    if (mode == 2 or mode == 4) {
        _ = mysql.mysql_field_seek(res, 0);
        var fi: usize = 0;
        while (fi < num_fields and fi < 64) : (fi += 1) {
            if (mysql.mysql_fetch_field(res)) |field| {
                field_names[fi] = std.mem.span(fieldName(field));
            } else {
                field_names[fi] = "";
            }
        }
    }

    var col: usize = 0;
    while (col < num_fields) : (col += 1) {
        const val = if (row_ptrs[col]) |ptr| blk: {
            const len = lengths[col];
            const s = try ctx.createString(ptr[0..len]);
            break :blk Value{ .string = Value.String.borrowed(s) };
        } else Value.null;

        if (mode == 3 or mode == 4) try row.append(ctx.allocator, val);
        if (mode == 2 or mode == 4) {
            try row.set(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString(field_names[col])) }, val);
        }
    }

    const cur = obj.get("__current_row");
    if (cur == .int) try obj.set(ctx.allocator, "__current_row", .{ .int = cur.int + 1 });
    return NativeResult.borrowed(.{ .array = row });
}

pub fn stmtFetchAll(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!NativeResult {
    var result = try ctx.createArray();
    while (true) {
        const row = (try stmtFetch(ctx, obj, args)).value;
        if (row == .bool and !row.bool) break;
        try result.append(ctx.allocator, row);
    }
    return NativeResult.borrowed(.{ .array = result });
}

pub fn stmtFetchColumn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!NativeResult {
    const res = getRes(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const col_idx: usize = if (args.len >= 1 and args[0] == .int) @intCast(args[0].int) else 0;
    const row_ptrs = mysql.mysql_fetch_row(res) orelse return NativeResult.scalar(.{ .bool = false });
    const lengths = mysql.mysql_fetch_lengths(res) orelse return NativeResult.scalar(.{ .bool = false });
    const num_fields = mysql.mysql_num_fields(res);
    if (col_idx >= num_fields) return NativeResult.scalar(.{ .bool = false });

    if (row_ptrs[col_idx]) |ptr| {
        const len = lengths[col_idx];
        return try NativeResult.copyString(ctx.allocator, ptr[0..len]);
    }
    return NativeResult.scalar(.null);
}

pub fn stmtColumnCount(obj: *PhpObject) RuntimeError!NativeResult {
    const res = getRes(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(mysql.mysql_num_fields(res)) });
}

pub fn stmtCloseCursor(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    if (getRes(obj)) |res| {
        mysql.mysql_free_result(res);
        setRes(obj, null);
    }
    try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

pub fn lastInsertId(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return NativeResult.literal("0");
    const id = mysql.mysql_insert_id(conn);
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{id}) catch "0";
    return try NativeResult.copyString(ctx.allocator, s);
}

pub fn beginTransaction(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return NativeResult.scalar(.{ .bool = false });
    _ = ctx;
    return NativeResult.scalar(.{ .bool = mysql.mysql_autocommit(conn, 0) == 0 });
}

pub fn commit(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return NativeResult.scalar(.{ .bool = false });
    _ = ctx;
    const ok = mysql.mysql_commit(conn) == 0;
    _ = mysql.mysql_autocommit(conn, 1);
    return NativeResult.scalar(.{ .bool = ok });
}

pub fn rollBack(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return NativeResult.scalar(.{ .bool = false });
    _ = ctx;
    const ok = mysql.mysql_rollback(conn) == 0;
    _ = mysql.mysql_autocommit(conn, 1);
    return NativeResult.scalar(.{ .bool = ok });
}

pub fn errorInfo(ctx: *NativeContext, obj: *PhpObject) RuntimeError!NativeResult {
    const conn = getConn(obj) orelse return NativeResult.scalar(.null);
    var arr = try ctx.createArray();
    const msg = std.mem.span(mysql.mysql_error(conn));
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("00000") });
    try arr.append(ctx.allocator, .null);
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString(msg)) });
    return NativeResult.borrowed(.{ .array = arr });
}

pub fn cleanupStatement(obj: *PhpObject) void {
    if (getRes(obj)) |res| {
        mysql.mysql_free_result(res);
        setRes(obj, null);
    }
}

pub fn cleanupConnection(obj: *PhpObject) void {
    if (obj.native.get(mysql.MYSQL, .pdo_mysql)) |conn| {
        mysql.mysql_close(conn);
        obj.native.ptr = 0;
    }
}
