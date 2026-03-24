const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };
const pdo = @import("pdo.zig");

const pg = struct {
    const PGconn = opaque {};
    const PGresult = opaque {};

    const CONNECTION_OK: c_int = 0;
    const PGRES_COMMAND_OK: c_int = 1;
    const PGRES_TUPLES_OK: c_int = 2;

    extern "pq" fn PQconnectdb(conninfo: [*:0]const u8) callconv(.c) ?*PGconn;
    extern "pq" fn PQstatus(conn: *PGconn) callconv(.c) c_int;
    extern "pq" fn PQfinish(conn: *PGconn) callconv(.c) void;
    extern "pq" fn PQerrorMessage(conn: *PGconn) callconv(.c) [*:0]const u8;
    extern "pq" fn PQexec(conn: *PGconn, query: [*:0]const u8) callconv(.c) ?*PGresult;
    extern "pq" fn PQexecParams(conn: *PGconn, command: [*:0]const u8, nParams: c_int, paramTypes: ?[*]const c_uint, paramValues: ?[*]const ?[*:0]const u8, paramLengths: ?[*]const c_int, paramFormats: ?[*]const c_int, resultFormat: c_int) callconv(.c) ?*PGresult;
    extern "pq" fn PQresultStatus(res: *PGresult) callconv(.c) c_int;
    extern "pq" fn PQresultErrorMessage(res: *PGresult) callconv(.c) [*:0]const u8;
    extern "pq" fn PQclear(res: *PGresult) callconv(.c) void;
    extern "pq" fn PQntuples(res: *PGresult) callconv(.c) c_int;
    extern "pq" fn PQnfields(res: *PGresult) callconv(.c) c_int;
    extern "pq" fn PQfname(res: *PGresult, field_num: c_int) callconv(.c) ?[*:0]const u8;
    extern "pq" fn PQgetvalue(res: *PGresult, tup_num: c_int, field_num: c_int) callconv(.c) [*:0]const u8;
    extern "pq" fn PQgetisnull(res: *PGresult, tup_num: c_int, field_num: c_int) callconv(.c) c_int;
    extern "pq" fn PQcmdTuples(res: *PGresult) callconv(.c) [*:0]const u8;
};

fn getConn(obj: *PhpObject) ?*pg.PGconn {
    return pdo.getOpaquePtr(pg.PGconn, obj, "__db_ptr");
}

fn getRes(obj: *PhpObject) ?*pg.PGresult {
    return pdo.getOpaquePtr(pg.PGresult, obj, "__res_ptr");
}

pub fn connect(ctx: *NativeContext, obj: *PhpObject, rest: []const u8, args: []const Value) RuntimeError!Value {
    // build libpq connection string from DSN params
    // pgsql:host=localhost;port=5432;dbname=test -> "host=localhost port=5432 dbname=test user=X password=Y"
    var conninfo = std.ArrayListUnmanaged(u8){};

    var iter = std.mem.splitScalar(u8, rest, ';');
    while (iter.next()) |param| {
        if (std.mem.indexOf(u8, param, "=")) |eq| {
            const key = std.mem.trim(u8, param[0..eq], " ");
            const val = std.mem.trim(u8, param[eq + 1 ..], " ");
            if (conninfo.items.len > 0) try conninfo.append(ctx.allocator, ' ');
            try conninfo.appendSlice(ctx.allocator, key);
            try conninfo.append(ctx.allocator, '=');
            try conninfo.appendSlice(ctx.allocator, val);
        }
    }

    if (args.len >= 2 and args[1] == .string) {
        if (conninfo.items.len > 0) try conninfo.append(ctx.allocator, ' ');
        try conninfo.appendSlice(ctx.allocator, "user=");
        try conninfo.appendSlice(ctx.allocator, args[1].string);
    }
    if (args.len >= 3 and args[2] == .string) {
        if (conninfo.items.len > 0) try conninfo.append(ctx.allocator, ' ');
        try conninfo.appendSlice(ctx.allocator, "password=");
        try conninfo.appendSlice(ctx.allocator, args[2].string);
    }

    try conninfo.append(ctx.allocator, 0);
    const conninfo_z: [*:0]const u8 = @ptrCast(conninfo.items.ptr);
    try ctx.strings.append(ctx.allocator, conninfo.items);

    const conn = pg.PQconnectdb(conninfo_z) orelse return pdo.throwPdo(ctx, "Failed to connect to PostgreSQL");
    if (pg.PQstatus(conn) != pg.CONNECTION_OK) {
        const msg = std.mem.span(pg.PQerrorMessage(conn));
        pg.PQfinish(conn);
        return pdo.throwPdo(ctx, msg);
    }

    try obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(conn)) });
    return .null;
}

pub fn exec(ctx: *NativeContext, obj: *PhpObject, sql: []const u8) RuntimeError!Value {
    const conn = getConn(obj) orelse return pdo.throwPdo(ctx, "Database not connected");
    const sql_z = try pdo.dupeZ(ctx, sql);
    const res = pg.PQexec(conn, sql_z) orelse return pdo.throwPdo(ctx, std.mem.span(pg.PQerrorMessage(conn)));
    const status = pg.PQresultStatus(res);
    if (status != pg.PGRES_COMMAND_OK and status != pg.PGRES_TUPLES_OK) {
        const msg = std.mem.span(pg.PQresultErrorMessage(res));
        pg.PQclear(res);
        return pdo.throwPdo(ctx, msg);
    }
    const affected = std.fmt.parseInt(i64, std.mem.span(pg.PQcmdTuples(res)), 10) catch 0;
    pg.PQclear(res);
    return .{ .int = affected };
}

pub fn query(ctx: *NativeContext, obj: *PhpObject, sql: []const u8) RuntimeError!Value {
    const conn = getConn(obj) orelse return pdo.throwPdo(ctx, "Database not connected");
    const sql_z = try pdo.dupeZ(ctx, sql);
    const res = pg.PQexec(conn, sql_z) orelse return pdo.throwPdo(ctx, std.mem.span(pg.PQerrorMessage(conn)));
    const status = pg.PQresultStatus(res);
    if (status != pg.PGRES_TUPLES_OK and status != pg.PGRES_COMMAND_OK) {
        const msg = std.mem.span(pg.PQresultErrorMessage(res));
        pg.PQclear(res);
        return pdo.throwPdo(ctx, msg);
    }

    const stmt_obj = try ctx.createObject("PDOStatement");
    try stmt_obj.set(ctx.allocator, "__driver", .{ .string = "pgsql" });
    try stmt_obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(conn)) });
    try stmt_obj.set(ctx.allocator, "__res_ptr", .{ .int = @intCast(@intFromPtr(res)) });
    try stmt_obj.set(ctx.allocator, "__current_row", .{ .int = 0 });
    try stmt_obj.set(ctx.allocator, "__has_row", .{ .bool = pg.PQntuples(res) > 0 });
    try stmt_obj.set(ctx.allocator, "__stepped", .{ .bool = true });
    return .{ .object = stmt_obj };
}

pub fn prepare(ctx: *NativeContext, obj: *PhpObject, sql: []const u8) RuntimeError!Value {
    const conn = getConn(obj) orelse return pdo.throwPdo(ctx, "Database not connected");

    // rewrite ? and :name to $1, $2, ... for postgres
    var rewritten = std.ArrayListUnmanaged(u8){};
    var param_names = std.ArrayListUnmanaged([]const u8){};
    var param_count: usize = 0;
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
        } else if (!in_string and sql[i] == '?') {
            param_count += 1;
            var buf: [12]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "${d}", .{param_count}) catch "$0";
            try rewritten.appendSlice(ctx.allocator, s);
            i += 1;
        } else if (!in_string and sql[i] == ':' and i + 1 < sql.len and std.ascii.isAlphabetic(sql[i + 1])) {
            const start = i + 1;
            i += 1;
            while (i < sql.len and (std.ascii.isAlphanumeric(sql[i]) or sql[i] == '_')) i += 1;
            param_count += 1;
            try param_names.append(ctx.allocator, sql[start..i]);
            var buf: [12]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "${d}", .{param_count}) catch "$0";
            try rewritten.appendSlice(ctx.allocator, s);
        } else {
            try rewritten.append(ctx.allocator, sql[i]);
            i += 1;
        }
    }

    const stmt_obj = try ctx.createObject("PDOStatement");
    try stmt_obj.set(ctx.allocator, "__driver", .{ .string = "pgsql" });
    try stmt_obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(conn)) });
    try stmt_obj.set(ctx.allocator, "__res_ptr", .{ .int = 0 });
    try stmt_obj.set(ctx.allocator, "__current_row", .{ .int = 0 });
    try stmt_obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    try stmt_obj.set(ctx.allocator, "__stepped", .{ .bool = false });
    try stmt_obj.set(ctx.allocator, "__param_count", .{ .int = @intCast(param_count) });

    const sql_owned = try rewritten.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, sql_owned);
    try stmt_obj.set(ctx.allocator, "__sql", .{ .string = sql_owned });

    if (param_names.items.len > 0) {
        var map = try ctx.createArray();
        for (param_names.items, 0..) |name, idx| {
            try map.set(ctx.allocator, .{ .string = name }, .{ .int = @intCast(idx) });
        }
        try stmt_obj.set(ctx.allocator, "__param_map", .{ .array = map });
    }
    param_names.deinit(ctx.allocator);

    return .{ .object = stmt_obj };
}

pub fn stmtExecute(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!Value {
    const conn = getConn(obj) orelse return .{ .bool = false };
    const sql_val = obj.get("__sql");
    if (sql_val != .string) return .{ .bool = false };
    const sql_z = try pdo.dupeZ(ctx, sql_val.string);

    // free previous result
    if (getRes(obj)) |old_res| {
        pg.PQclear(old_res);
        try obj.set(ctx.allocator, "__res_ptr", .{ .int = 0 });
    }

    const pc_val = obj.get("__param_count");
    const param_count: usize = if (pc_val == .int and pc_val.int > 0) @intCast(pc_val.int) else 0;

    if (param_count > 0 and args.len >= 1 and args[0] == .array) {
        const params = args[0].array;
        const param_map_val = obj.get("__param_map");
        const param_map = if (param_map_val == .array) param_map_val.array else null;

        // build param values array
        var param_values = try ctx.allocator.alloc(?[*:0]const u8, param_count);
        defer ctx.allocator.free(param_values);
        @memset(param_values, null);

        if (param_map) |pm| {
            // named params
            for (params.entries.items) |entry| {
                var name = if (entry.key == .string) entry.key.string else continue;
                if (name.len > 0 and name[0] == ':') name = name[1..];
                const idx_val = pm.get(.{ .string = name });
                if (idx_val == .int) {
                    const idx: usize = @intCast(idx_val.int);
                    if (idx < param_count) {
                        if (entry.value == .null) {
                            param_values[idx] = null;
                        } else {
                            param_values[idx] = try valueToZ(ctx, entry.value);
                        }
                    }
                }
            }
        } else {
            // positional params
            for (params.entries.items, 0..) |entry, idx| {
                if (idx >= param_count) break;
                if (entry.value == .null) {
                    param_values[idx] = null;
                } else {
                    param_values[idx] = try valueToZ(ctx, entry.value);
                }
            }
        }

        const res = pg.PQexecParams(conn, sql_z, @intCast(param_count), null, param_values.ptr, null, null, 0) orelse return .{ .bool = false };
        const status = pg.PQresultStatus(res);
        if (status != pg.PGRES_TUPLES_OK and status != pg.PGRES_COMMAND_OK) {
            const msg = std.mem.span(pg.PQresultErrorMessage(res));
            pg.PQclear(res);
            return pdo.throwPdo(ctx, msg);
        }
        try obj.set(ctx.allocator, "__res_ptr", .{ .int = @intCast(@intFromPtr(res)) });
        try obj.set(ctx.allocator, "__current_row", .{ .int = 0 });
        try obj.set(ctx.allocator, "__has_row", .{ .bool = pg.PQntuples(res) > 0 });
        try obj.set(ctx.allocator, "__row_count", .{ .int = std.fmt.parseInt(i64, std.mem.span(pg.PQcmdTuples(res)), 10) catch @intCast(pg.PQntuples(res)) });
    } else {
        const res = pg.PQexec(conn, sql_z) orelse return .{ .bool = false };
        const status = pg.PQresultStatus(res);
        if (status != pg.PGRES_TUPLES_OK and status != pg.PGRES_COMMAND_OK) {
            const msg = std.mem.span(pg.PQresultErrorMessage(res));
            pg.PQclear(res);
            return pdo.throwPdo(ctx, msg);
        }
        try obj.set(ctx.allocator, "__res_ptr", .{ .int = @intCast(@intFromPtr(res)) });
        try obj.set(ctx.allocator, "__current_row", .{ .int = 0 });
        try obj.set(ctx.allocator, "__has_row", .{ .bool = pg.PQntuples(res) > 0 });
        try obj.set(ctx.allocator, "__row_count", .{ .int = std.fmt.parseInt(i64, std.mem.span(pg.PQcmdTuples(res)), 10) catch @intCast(pg.PQntuples(res)) });
    }
    try obj.set(ctx.allocator, "__stepped", .{ .bool = true });
    return .{ .bool = true };
}

fn valueToZ(ctx: *NativeContext, val: Value) !?[*:0]const u8 {
    switch (val) {
        .null => return null,
        .bool => |b| return if (b) "1" else "0",
        .int => |i| {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return "0";
            const z = try pdo.dupeZ(ctx, s);
            return z.ptr;
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return "0";
            const z = try pdo.dupeZ(ctx, s);
            return z.ptr;
        },
        .string => |s| {
            const z = try pdo.dupeZ(ctx, s);
            return z.ptr;
        },
        else => return null,
    }
}

pub fn stmtFetch(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!Value {
    const res = getRes(obj) orelse return .{ .bool = false };
    const cur_val = obj.get("__current_row");
    const current_row: c_int = if (cur_val == .int) @intCast(cur_val.int) else 0;
    const total_rows = pg.PQntuples(res);
    if (current_row >= total_rows) return .{ .bool = false };

    const mode: i64 = if (args.len >= 1 and args[0] == .int) args[0].int else 4;
    const num_fields = pg.PQnfields(res);
    var row = try ctx.createArray();

    var col: c_int = 0;
    while (col < num_fields) : (col += 1) {
        const val = if (pg.PQgetisnull(res, current_row, col) != 0) Value.null else blk: {
            const s = std.mem.span(pg.PQgetvalue(res, current_row, col));
            break :blk Value{ .string = try ctx.createString(s) };
        };

        if (mode == 3 or mode == 4) try row.append(ctx.allocator, val);
        if (mode == 2 or mode == 4) {
            if (pg.PQfname(res, col)) |name_ptr| {
                const name = std.mem.span(name_ptr);
                try row.set(ctx.allocator, .{ .string = try ctx.createString(name) }, val);
            }
        }
    }

    try obj.set(ctx.allocator, "__current_row", .{ .int = current_row + 1 });
    return .{ .array = row };
}

pub fn stmtFetchAll(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!Value {
    var result = try ctx.createArray();
    while (true) {
        const row = try stmtFetch(ctx, obj, args);
        if (row == .bool and !row.bool) break;
        try result.append(ctx.allocator, row);
    }
    return .{ .array = result };
}

pub fn stmtFetchColumn(ctx: *NativeContext, obj: *PhpObject, args: []const Value) RuntimeError!Value {
    const res = getRes(obj) orelse return .{ .bool = false };
    const cur_val = obj.get("__current_row");
    const current_row: c_int = if (cur_val == .int) @intCast(cur_val.int) else 0;
    if (current_row >= pg.PQntuples(res)) return .{ .bool = false };

    const col: c_int = if (args.len >= 1 and args[0] == .int) @intCast(args[0].int) else 0;
    if (col >= pg.PQnfields(res)) return .{ .bool = false };

    try obj.set(ctx.allocator, "__current_row", .{ .int = current_row + 1 });

    if (pg.PQgetisnull(res, current_row, col) != 0) return .null;
    const s = std.mem.span(pg.PQgetvalue(res, current_row, col));
    return .{ .string = try ctx.createString(s) };
}

pub fn stmtColumnCount(obj: *PhpObject) RuntimeError!Value {
    const res = getRes(obj) orelse return .{ .int = 0 };
    return .{ .int = @intCast(pg.PQnfields(res)) };
}

pub fn stmtCloseCursor(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    if (getRes(obj)) |res| {
        pg.PQclear(res);
        try obj.set(ctx.allocator, "__res_ptr", .{ .int = 0 });
    }
    try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    try obj.set(ctx.allocator, "__current_row", .{ .int = 0 });
    return .{ .bool = true };
}

pub fn lastInsertId(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    // postgres uses RETURNING or lastval() for insert IDs
    const conn = getConn(obj) orelse return .{ .string = "0" };
    const sql_z: [*:0]const u8 = "SELECT lastval()";
    const res = pg.PQexec(conn, sql_z) orelse return .{ .string = "0" };
    defer pg.PQclear(res);
    if (pg.PQresultStatus(res) != pg.PGRES_TUPLES_OK or pg.PQntuples(res) == 0) return .{ .string = "0" };
    const s = std.mem.span(pg.PQgetvalue(res, 0, 0));
    return .{ .string = try ctx.createString(s) };
}

pub fn beginTransaction(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    const conn = getConn(obj) orelse return .{ .bool = false };
    const res = pg.PQexec(conn, "BEGIN") orelse return .{ .bool = false };
    const ok = pg.PQresultStatus(res) == pg.PGRES_COMMAND_OK;
    pg.PQclear(res);
    _ = ctx;
    return .{ .bool = ok };
}

pub fn commit(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    const conn = getConn(obj) orelse return .{ .bool = false };
    const res = pg.PQexec(conn, "COMMIT") orelse return .{ .bool = false };
    const ok = pg.PQresultStatus(res) == pg.PGRES_COMMAND_OK;
    pg.PQclear(res);
    _ = ctx;
    return .{ .bool = ok };
}

pub fn rollBack(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    const conn = getConn(obj) orelse return .{ .bool = false };
    const res = pg.PQexec(conn, "ROLLBACK") orelse return .{ .bool = false };
    const ok = pg.PQresultStatus(res) == pg.PGRES_COMMAND_OK;
    pg.PQclear(res);
    _ = ctx;
    return .{ .bool = ok };
}

pub fn errorInfo(ctx: *NativeContext, obj: *PhpObject) RuntimeError!Value {
    const conn = getConn(obj) orelse return .null;
    var arr = try ctx.createArray();
    const msg = std.mem.span(pg.PQerrorMessage(conn));
    try arr.append(ctx.allocator, .{ .string = "00000" });
    try arr.append(ctx.allocator, .null);
    try arr.append(ctx.allocator, .{ .string = try ctx.createString(msg) });
    return .{ .array = arr };
}

pub fn cleanupStatement(obj: *PhpObject) void {
    if (getRes(obj)) |res| {
        pg.PQclear(res);
        obj.properties.put(std.heap.page_allocator, "__res_ptr", .{ .int = 0 }) catch {};
    }
}

pub fn cleanupConnection(obj: *PhpObject) void {
    if (getConn(obj)) |conn| {
        pg.PQfinish(conn);
        obj.properties.put(std.heap.page_allocator, "__db_ptr", .{ .int = 0 }) catch {};
    }
}
