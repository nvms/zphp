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

const sqlite = struct {
    const Db = opaque {};
    const Stmt = opaque {};

    const OK: c_int = 0;
    const ROW: c_int = 100;
    const DONE: c_int = 101;

    const INTEGER: c_int = 1;
    const FLOAT: c_int = 2;
    const TEXT: c_int = 3;
    const BLOB: c_int = 4;
    const NULL: c_int = 5;

    extern "sqlite3" fn sqlite3_open(filename: [*:0]const u8, ppDb: *?*Db) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_close_v2(db: *Db) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_exec(db: *Db, sql: [*:0]const u8, callback: ?*anyopaque, arg: ?*anyopaque, errmsg: ?*[*:0]u8) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_prepare_v2(db: *Db, sql: [*:0]const u8, nByte: c_int, ppStmt: *?*Stmt, pzTail: ?*[*:0]const u8) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_step(stmt: *Stmt) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_finalize(stmt: *Stmt) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_reset(stmt: *Stmt) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_column_count(stmt: *Stmt) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_column_name(stmt: *Stmt, n: c_int) callconv(.c) ?[*:0]const u8;
    extern "sqlite3" fn sqlite3_column_type(stmt: *Stmt, n: c_int) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_column_int64(stmt: *Stmt, n: c_int) callconv(.c) i64;
    extern "sqlite3" fn sqlite3_column_double(stmt: *Stmt, n: c_int) callconv(.c) f64;
    extern "sqlite3" fn sqlite3_column_text(stmt: *Stmt, n: c_int) callconv(.c) ?[*:0]const u8;
    extern "sqlite3" fn sqlite3_column_bytes(stmt: *Stmt, n: c_int) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_bind_null(stmt: *Stmt, n: c_int) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_bind_int64(stmt: *Stmt, n: c_int, val: i64) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_bind_double(stmt: *Stmt, n: c_int, val: f64) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_bind_text(stmt: *Stmt, n: c_int, val: [*]const u8, nBytes: c_int, destructor: ?*const fn (?*anyopaque) callconv(.c) void) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_bind_parameter_index(stmt: *Stmt, name: [*:0]const u8) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_changes(db: *Db) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_last_insert_rowid(db: *Db) callconv(.c) i64;
    extern "sqlite3" fn sqlite3_errmsg(db: *Db) callconv(.c) [*:0]const u8;
};

pub fn getOpaquePtr(comptime T: type, obj: *PhpObject, prop: []const u8) ?*T {
    const v = obj.get(prop);
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn getDbPtr(obj: *PhpObject) ?*sqlite.Db {
    return getOpaquePtr(sqlite.Db, obj, "__db_ptr");
}

fn getStmtPtr(obj: *PhpObject) ?*sqlite.Stmt {
    return getOpaquePtr(sqlite.Stmt, obj, "__stmt_ptr");
}

pub fn throwPdo(ctx: *NativeContext, msg: []const u8) RuntimeError!Value {
    // honor ATTR_ERRMODE: silent (0) returns false, warning (1) returns false,
    // exception (2) throws PDOException. default in PHP 8 is exception, but for
    // backward-compat zphp defaults the construct path to exception too
    if (ctx.vm.currentFrame().vars.get("$this")) |this_v| {
        if (this_v == .object) {
            const obj = this_v.object;
            try obj.set(ctx.allocator, "__error_code", .{ .string = "HY000" });
            const owned = try ctx.createString(msg);
            try obj.set(ctx.allocator, "__error_message", .{ .string = owned });
            const mode = obj.get("__errmode");
            const m: i64 = if (mode == .int) mode.int else 2;
            if (m != 2) return .{ .bool = false };
        }
    }
    if (try ctx.vm.throwBuiltinException("PDOException", msg)) return .null;
    return error.RuntimeError;
}

pub fn dupeZ(ctx: *NativeContext, s: []const u8) ![:0]u8 {
    const z = try ctx.allocator.alloc(u8, s.len + 1);
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    try ctx.strings.append(ctx.allocator, z);
    return z[0..s.len :0];
}

pub fn register(vm: *VM, a: Allocator) !void {
    var pdo_def = ClassDef{ .name = "PDO" };
    try pdo_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try pdo_def.methods.put(a, "exec", .{ .name = "exec", .arity = 1 });
    try pdo_def.methods.put(a, "query", .{ .name = "query", .arity = 1 });
    try pdo_def.methods.put(a, "prepare", .{ .name = "prepare", .arity = 1 });
    try pdo_def.methods.put(a, "lastInsertId", .{ .name = "lastInsertId", .arity = 0 });
    try pdo_def.methods.put(a, "beginTransaction", .{ .name = "beginTransaction", .arity = 0 });
    try pdo_def.methods.put(a, "commit", .{ .name = "commit", .arity = 0 });
    try pdo_def.methods.put(a, "rollBack", .{ .name = "rollBack", .arity = 0 });
    try pdo_def.methods.put(a, "errorInfo", .{ .name = "errorInfo", .arity = 0 });
    try pdo_def.methods.put(a, "errorCode", .{ .name = "errorCode", .arity = 0 });
    try pdo_def.methods.put(a, "setAttribute", .{ .name = "setAttribute", .arity = 2 });
    try pdo_def.methods.put(a, "getAttribute", .{ .name = "getAttribute", .arity = 1 });
    try pdo_def.methods.put(a, "quote", .{ .name = "quote", .arity = 1 });
    try pdo_def.methods.put(a, "inTransaction", .{ .name = "inTransaction", .arity = 0 });
    try pdo_def.methods.put(a, "getAvailableDrivers", .{ .name = "getAvailableDrivers", .arity = 0, .is_static = true });

    // PDO constants as static properties
    try pdo_def.static_props.put(a, "FETCH_BOTH", .{ .int = 4 });
    try pdo_def.static_props.put(a, "FETCH_ASSOC", .{ .int = 2 });
    try pdo_def.static_props.put(a, "FETCH_NUM", .{ .int = 3 });
    try pdo_def.static_props.put(a, "FETCH_OBJ", .{ .int = 5 });
    try pdo_def.static_props.put(a, "FETCH_COLUMN", .{ .int = 7 });
    try pdo_def.static_props.put(a, "FETCH_KEY_PAIR", .{ .int = 12 });
    try pdo_def.static_props.put(a, "FETCH_UNIQUE", .{ .int = 196608 });
    try pdo_def.static_props.put(a, "FETCH_GROUP", .{ .int = 65536 });
    try pdo_def.static_props.put(a, "FETCH_CLASS", .{ .int = 8 });
    try pdo_def.static_props.put(a, "FETCH_LAZY", .{ .int = 1 });
    try pdo_def.static_props.put(a, "FETCH_NAMED", .{ .int = 11 });
    try pdo_def.static_props.put(a, "ATTR_ERRMODE", .{ .int = 3 });
    try pdo_def.static_props.put(a, "ATTR_DEFAULT_FETCH_MODE", .{ .int = 19 });
    try pdo_def.static_props.put(a, "ERRMODE_EXCEPTION", .{ .int = 2 });
    try pdo_def.static_props.put(a, "ERRMODE_SILENT", .{ .int = 0 });
    try pdo_def.static_props.put(a, "ERRMODE_WARNING", .{ .int = 1 });
    try pdo_def.static_props.put(a, "ATTR_CASE", .{ .int = 8 });
    try pdo_def.static_props.put(a, "CASE_NATURAL", .{ .int = 0 });
    try pdo_def.static_props.put(a, "CASE_LOWER", .{ .int = 2 });
    try pdo_def.static_props.put(a, "CASE_UPPER", .{ .int = 1 });
    try pdo_def.static_props.put(a, "ATTR_PERSISTENT", .{ .int = 12 });
    try pdo_def.static_props.put(a, "ATTR_AUTOCOMMIT", .{ .int = 0 });
    try pdo_def.static_props.put(a, "ATTR_EMULATE_PREPARES", .{ .int = 20 });
    try pdo_def.static_props.put(a, "ATTR_DRIVER_NAME", .{ .int = 16 });
    try pdo_def.static_props.put(a, "ATTR_SERVER_VERSION", .{ .int = 4 });
    try pdo_def.static_props.put(a, "ATTR_CLIENT_VERSION", .{ .int = 5 });
    try pdo_def.static_props.put(a, "PARAM_BOOL", .{ .int = 5 });
    try pdo_def.static_props.put(a, "PARAM_LOB", .{ .int = 3 });
    try pdo_def.static_props.put(a, "PARAM_NULL", .{ .int = 0 });
    try pdo_def.static_props.put(a, "PARAM_INT", .{ .int = 1 });
    try pdo_def.static_props.put(a, "PARAM_STR", .{ .int = 2 });

    try vm.classes.put(a, "PDO", pdo_def);

    try vm.native_fns.put(a, "PDO::__construct", pdoConstruct);
    try vm.native_fns.put(a, "PDO::connect", pdoConnect);
    try vm.native_fns.put(a, "PDO::exec", pdoExec);
    try vm.native_fns.put(a, "PDO::query", pdoQuery);
    try vm.native_fns.put(a, "PDO::quote", pdoQuote);
    try vm.native_fns.put(a, "PDO::inTransaction", pdoInTransaction);
    try vm.native_fns.put(a, "PDO::getAvailableDrivers", pdoGetAvailableDrivers);
    try vm.native_fns.put(a, "PDO::errorCode", pdoErrorCode);
    try vm.native_fns.put(a, "PDO::prepare", pdoPrepare);
    try vm.native_fns.put(a, "PDO::lastInsertId", pdoLastInsertId);
    try vm.native_fns.put(a, "PDO::beginTransaction", pdoBeginTransaction);
    try vm.native_fns.put(a, "PDO::commit", pdoCommit);
    try vm.native_fns.put(a, "PDO::rollBack", pdoRollBack);
    try vm.native_fns.put(a, "PDO::errorInfo", pdoErrorInfo);
    try vm.native_fns.put(a, "PDO::setAttribute", pdoSetAttribute);
    try vm.native_fns.put(a, "PDO::getAttribute", pdoGetAttribute);

    var stmt_def = ClassDef{ .name = "PDOStatement" };
    try stmt_def.interfaces.append(a, "Iterator");
    try stmt_def.interfaces.append(a, "Traversable");
    try stmt_def.methods.put(a, "execute", .{ .name = "execute", .arity = 1 });
    try stmt_def.methods.put(a, "fetch", .{ .name = "fetch", .arity = 1 });
    try stmt_def.methods.put(a, "fetchAll", .{ .name = "fetchAll", .arity = 1 });
    try stmt_def.methods.put(a, "fetchColumn", .{ .name = "fetchColumn", .arity = 1 });
    try stmt_def.methods.put(a, "fetchObject", .{ .name = "fetchObject", .arity = 2 });
    try stmt_def.methods.put(a, "rowCount", .{ .name = "rowCount", .arity = 0 });
    try stmt_def.methods.put(a, "columnCount", .{ .name = "columnCount", .arity = 0 });
    try stmt_def.methods.put(a, "closeCursor", .{ .name = "closeCursor", .arity = 0 });
    try stmt_def.methods.put(a, "setFetchMode", .{ .name = "setFetchMode", .arity = 1 });
    try stmt_def.methods.put(a, "bindValue", .{ .name = "bindValue", .arity = 2 });
    try stmt_def.methods.put(a, "bindParam", .{ .name = "bindParam", .arity = 2 });
    try stmt_def.methods.put(a, "errorCode", .{ .name = "errorCode", .arity = 0 });
    try stmt_def.methods.put(a, "errorInfo", .{ .name = "errorInfo", .arity = 0 });
    try stmt_def.methods.put(a, "debugDumpParams", .{ .name = "debugDumpParams", .arity = 0 });
    try stmt_def.methods.put(a, "getColumnMeta", .{ .name = "getColumnMeta", .arity = 1 });
    try stmt_def.methods.put(a, "nextRowset", .{ .name = "nextRowset", .arity = 0 });
    try stmt_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try stmt_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try stmt_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try stmt_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try stmt_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try vm.classes.put(a, "PDOStatement", stmt_def);

    try vm.native_fns.put(a, "PDOStatement::execute", stmtExecute);
    try vm.native_fns.put(a, "PDOStatement::fetch", stmtFetch);
    try vm.native_fns.put(a, "PDOStatement::fetchAll", stmtFetchAll);
    try vm.native_fns.put(a, "PDOStatement::fetchColumn", stmtFetchColumn);
    try vm.native_fns.put(a, "PDOStatement::fetchObject", stmtFetchObject);
    try vm.native_fns.put(a, "PDOStatement::rowCount", stmtRowCount);
    try vm.native_fns.put(a, "PDOStatement::columnCount", stmtColumnCount);
    try vm.native_fns.put(a, "PDOStatement::closeCursor", stmtCloseCursor);
    try vm.native_fns.put(a, "PDOStatement::setFetchMode", stmtSetFetchMode);
    try vm.native_fns.put(a, "PDOStatement::bindValue", stmtBindValue);
    try vm.native_fns.put(a, "PDOStatement::bindParam", stmtBindValue);
    try vm.native_fns.put(a, "PDOStatement::errorCode", stmtErrorCode);
    try vm.native_fns.put(a, "PDOStatement::errorInfo", stmtErrorInfo);
    try vm.native_fns.put(a, "PDOStatement::debugDumpParams", stmtDebugDumpParams);
    try vm.native_fns.put(a, "PDOStatement::getColumnMeta", stmtGetColumnMeta);
    try vm.native_fns.put(a, "PDOStatement::nextRowset", stmtNextRowset);
    try vm.native_fns.put(a, "PDOStatement::rewind", stmtIterRewind);
    try vm.native_fns.put(a, "PDOStatement::current", stmtIterCurrent);
    try vm.native_fns.put(a, "PDOStatement::key", stmtIterKey);
    try vm.native_fns.put(a, "PDOStatement::next", stmtIterNext);
    try vm.native_fns.put(a, "PDOStatement::valid", stmtIterValid);
}

fn stmtIterRewind(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    try obj.set(ctx.allocator, "__iter_key", .{ .int = 0 });
    // fetch the first row
    const row = try stmtFetch(ctx, &.{});
    try obj.set(ctx.allocator, "__iter_current", row);
    return .null;
}

fn stmtIterCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    return obj.get("__iter_current");
}

fn stmtIterKey(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .int = 0 };
    return obj.get("__iter_key");
}

fn stmtIterNext(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const cur_key = Value.toInt(obj.get("__iter_key"));
    try obj.set(ctx.allocator, "__iter_key", .{ .int = cur_key + 1 });
    const row = try stmtFetch(ctx, &.{});
    try obj.set(ctx.allocator, "__iter_current", row);
    return .null;
}

fn stmtIterValid(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const cur = obj.get("__iter_current");
    return .{ .bool = cur == .array };
}

fn stmtFetchObject(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const row = try stmtFetch(ctx, &.{.{ .int = 2 }}); // FETCH_ASSOC
    if (row != .array) return .{ .bool = false };
    var class_name: []const u8 = "stdClass";
    if (args.len >= 1 and args[0] == .string) class_name = args[0].string;
    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = class_name };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    if (ctx.vm.classes.contains(class_name)) {
        try ctx.vm.initObjectProperties(obj, class_name);
    }
    for (row.array.entries.items) |entry| {
        if (entry.key == .string) try obj.set(ctx.allocator, entry.key.string, entry.value);
    }
    return .{ .object = obj };
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    // finalize statements first, then close databases
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "PDOStatement")) {
            const drv = getDriver(obj);
            if (std.mem.eql(u8, drv, "mysql")) {
                pdo_mysql.cleanupStatement(obj);
            } else if (std.mem.eql(u8, drv, "pgsql")) {
                pdo_pgsql.cleanupStatement(obj);
            } else {
                if (getStmtPtr(obj)) |stmt| {
                    _ = sqlite.sqlite3_finalize(stmt);
                    obj.properties.put(std.heap.page_allocator, "__stmt_ptr", .{ .int = 0 }) catch {};
                }
            }
        }
    }
    for (objects.items) |obj| {
        if (std.mem.eql(u8, obj.class_name, "PDO")) {
            const drv = getDriver(obj);
            if (std.mem.eql(u8, drv, "mysql")) {
                pdo_mysql.cleanupConnection(obj);
            } else if (std.mem.eql(u8, drv, "pgsql")) {
                pdo_pgsql.cleanupConnection(obj);
            } else {
                if (getDbPtr(obj)) |db| {
                    _ = sqlite.sqlite3_close_v2(db);
                    obj.properties.put(std.heap.page_allocator, "__db_ptr", .{ .int = 0 }) catch {};
                }
            }
        }
    }
}

// PDO methods

const pdo_mysql = @import("pdo_mysql.zig");
const pdo_pgsql = @import("pdo_pgsql.zig");

fn getDriver(obj: *PhpObject) []const u8 {
    const v = obj.get("__driver");
    if (v == .string) return v.string;
    return "sqlite";
}

fn pdoConnect(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = try ctx.createObject("PDO");
    const prev_this = ctx.vm.currentFrame().vars.get("$this");
    try ctx.vm.currentFrame().vars.put(ctx.vm.allocator, "$this", .{ .object = obj });
    defer {
        if (prev_this) |pt| {
            ctx.vm.currentFrame().vars.put(ctx.vm.allocator, "$this", pt) catch {};
        } else {
            _ = ctx.vm.currentFrame().vars.remove("$this");
        }
    }
    _ = try pdoConstruct(ctx, args);
    return .{ .object = obj };
}

fn pdoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .string) return throwPdo(ctx, "PDO::__construct() expects a DSN string");

    const dsn = args[0].string;
    const colon = std.mem.indexOf(u8, dsn, ":") orelse return throwPdo(ctx, "Invalid DSN: missing driver prefix");
    const driver = dsn[0..colon];
    const rest = dsn[colon + 1 ..];

    try obj.set(ctx.allocator, "__driver", .{ .string = driver });

    if (std.mem.eql(u8, driver, "sqlite")) {
        const path_z = try dupeZ(ctx, rest);
        var db: ?*sqlite.Db = null;
        const rc = sqlite.sqlite3_open(path_z, &db);
        if (rc != sqlite.OK or db == null) return throwPdo(ctx, "Failed to open database");
        try obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(db.?)) });
        return .null;
    }

    if (std.mem.eql(u8, driver, "mysql")) return pdo_mysql.connect(ctx, obj, rest, args);
    if (std.mem.eql(u8, driver, "pgsql")) return pdo_pgsql.connect(ctx, obj, rest, args);

    return throwPdo(ctx, "Unsupported PDO driver");
}

fn pdoExec(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .string) return throwPdo(ctx, "PDO::exec() expects a SQL string");
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.exec(ctx, obj, args[0].string);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.exec(ctx, obj, args[0].string);
    const db = getDbPtr(obj) orelse return throwPdo(ctx, "Database not connected");
    const sql_z = try dupeZ(ctx, args[0].string);
    var errmsg: ?[*:0]u8 = null;
    const rc = sqlite.sqlite3_exec(db, sql_z, null, null, @ptrCast(&errmsg));
    if (rc != sqlite.OK) {
        const msg = if (errmsg) |e| std.mem.span(e) else "SQL execution error";
        const result = try throwPdo(ctx, msg);
        if (result == .bool and !result.bool) return .{ .bool = false };
        return result;
    }
    return .{ .int = sqlite.sqlite3_changes(db) };
}

fn pdoQuery(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .string) return throwPdo(ctx, "PDO::query() expects a SQL string");
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.query(ctx, obj, args[0].string);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.query(ctx, obj, args[0].string);
    const db = getDbPtr(obj) orelse return throwPdo(ctx, "Database not connected");

    const sql_z = try dupeZ(ctx, args[0].string);
    var stmt_ptr: ?*sqlite.Stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(db, sql_z, -1, &stmt_ptr, null);
    if (rc != sqlite.OK or stmt_ptr == null) {
        const msg = std.mem.span(sqlite.sqlite3_errmsg(db));
        return throwPdo(ctx, msg);
    }

    const stmt_obj = try ctx.createObject("PDOStatement");
    try stmt_obj.set(ctx.allocator, "__stmt_ptr", .{ .int = @intCast(@intFromPtr(stmt_ptr.?)) });
    try stmt_obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(db)) });
    // step once to position on first row
    const step_rc = sqlite.sqlite3_step(stmt_ptr.?);
    try stmt_obj.set(ctx.allocator, "__has_row", .{ .bool = step_rc == sqlite.ROW });
    try stmt_obj.set(ctx.allocator, "__stepped", .{ .bool = true });

    return .{ .object = stmt_obj };
}

fn pdoPrepare(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .string) return throwPdo(ctx, "PDO::prepare() expects a SQL string");
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.prepare(ctx, obj, args[0].string);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.prepare(ctx, obj, args[0].string);
    const db = getDbPtr(obj) orelse return throwPdo(ctx, "Database not connected");

    const sql_z = try dupeZ(ctx, args[0].string);
    var stmt_ptr: ?*sqlite.Stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(db, sql_z, -1, &stmt_ptr, null);
    if (rc != sqlite.OK or stmt_ptr == null) {
        const msg = std.mem.span(sqlite.sqlite3_errmsg(db));
        return throwPdo(ctx, msg);
    }

    const stmt_obj = try ctx.createObject("PDOStatement");
    try stmt_obj.set(ctx.allocator, "__stmt_ptr", .{ .int = @intCast(@intFromPtr(stmt_ptr.?)) });
    try stmt_obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(db)) });
    try stmt_obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    try stmt_obj.set(ctx.allocator, "__stepped", .{ .bool = false });

    return .{ .object = stmt_obj };
}

fn pdoLastInsertId(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.lastInsertId(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.lastInsertId(ctx, obj);
    const db = getDbPtr(obj) orelse return .{ .string = "0" };
    const id = sqlite.sqlite3_last_insert_rowid(db);
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{id}) catch "0";
    return .{ .string = try ctx.createString(s) };
}

fn pdoBeginTransaction(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.beginTransaction(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.beginTransaction(ctx, obj);
    const db = getDbPtr(obj) orelse return .{ .bool = false };
    const rc = sqlite.sqlite3_exec(db, "BEGIN", null, null, null);
    if (rc == sqlite.OK) try obj.set(ctx.allocator, "__in_transaction", .{ .bool = true });
    return .{ .bool = rc == sqlite.OK };
}

fn pdoCommit(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.commit(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.commit(ctx, obj);
    const db = getDbPtr(obj) orelse return .{ .bool = false };
    const rc = sqlite.sqlite3_exec(db, "COMMIT", null, null, null);
    if (rc == sqlite.OK) try obj.set(ctx.allocator, "__in_transaction", .{ .bool = false });
    return .{ .bool = rc == sqlite.OK };
}

fn pdoRollBack(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.rollBack(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.rollBack(ctx, obj);
    const db = getDbPtr(obj) orelse return .{ .bool = false };
    const rc = sqlite.sqlite3_exec(db, "ROLLBACK", null, null, null);
    if (rc == sqlite.OK) try obj.set(ctx.allocator, "__in_transaction", .{ .bool = false });
    return .{ .bool = rc == sqlite.OK };
}

fn pdoErrorInfo(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.errorInfo(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.errorInfo(ctx, obj);
    const db = getDbPtr(obj) orelse return .null;
    var arr = try ctx.createArray();
    const msg = std.mem.span(sqlite.sqlite3_errmsg(db));
    try arr.append(ctx.allocator, .{ .string = "00000" });
    try arr.append(ctx.allocator, .null);
    try arr.append(ctx.allocator, .{ .string = try ctx.createString(msg) });
    return .{ .array = arr };
}

fn pdoSetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    if (args.len < 2) return .{ .bool = false };
    const attr = if (args[0] == .int) args[0].int else return .{ .bool = false };
    if (attr == 19) {
        try obj.set(ctx.allocator, "__default_fetch_mode", args[1]);
    } else if (attr == 3) {
        try obj.set(ctx.allocator, "__errmode", args[1]);
    }
    return .{ .bool = true };
}

fn pdoGetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    if (args.len < 1 or args[0] != .int) return .null;
    const attr = args[0].int;
    if (attr == 19) {
        const mode = obj.get("__default_fetch_mode");
        if (mode == .int) return mode;
        return .{ .int = 4 };
    }
    return .null;
}

// PDOStatement methods

fn stmtExecute(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtExecute(ctx, obj, args);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtExecute(ctx, obj, args);
    const stmt = getStmtPtr(obj) orelse return .{ .bool = false };

    _ = sqlite.sqlite3_reset(stmt);

    // bind parameters if provided
    if (args.len >= 1 and args[0] == .array) {
        try bindParams(ctx, stmt, args[0].array);
    }

    const rc = sqlite.sqlite3_step(stmt);
    try obj.set(ctx.allocator, "__has_row", .{ .bool = rc == sqlite.ROW });
    try obj.set(ctx.allocator, "__stepped", .{ .bool = true });

    if (rc != sqlite.ROW and rc != sqlite.DONE) {
        const db_val = obj.get("__db_ptr");
        if (db_val == .int and db_val.int != 0) {
            const db: *sqlite.Db = @ptrFromInt(@as(usize, @intCast(db_val.int)));
            const msg = std.mem.span(sqlite.sqlite3_errmsg(db));
            return throwPdo(ctx, msg);
        }
        return .{ .bool = false };
    }

    // store affected rows
    const db_val = obj.get("__db_ptr");
    if (db_val == .int and db_val.int != 0) {
        const db: *sqlite.Db = @ptrFromInt(@as(usize, @intCast(db_val.int)));
        try obj.set(ctx.allocator, "__row_count", .{ .int = sqlite.sqlite3_changes(db) });
    }

    return .{ .bool = true };
}

fn stmtFetch(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtFetch(ctx, obj, args);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtFetch(ctx, obj, args);
    const stmt = getStmtPtr(obj) orelse return .{ .bool = false };

    const has_row = obj.get("__has_row");
    const stepped = obj.get("__stepped");

    // if not yet stepped (shouldn't happen after execute), step now
    if (stepped != .bool or !stepped.bool) {
        const rc = sqlite.sqlite3_step(stmt);
        try obj.set(ctx.allocator, "__has_row", .{ .bool = rc == sqlite.ROW });
        try obj.set(ctx.allocator, "__stepped", .{ .bool = true });
        if (rc != sqlite.ROW) return .{ .bool = false };
    } else if (has_row != .bool or !has_row.bool) {
        return .{ .bool = false };
    }

    const mode: i64 = if (args.len >= 1 and args[0] == .int) args[0].int else getDefaultFetchMode(obj);

    if (mode == 5) {
        const row = try fetchRowAsObject(ctx, stmt);
        const next_rc = sqlite.sqlite3_step(stmt);
        try obj.set(ctx.allocator, "__has_row", .{ .bool = next_rc == sqlite.ROW });
        return row;
    }

    const row = try fetchRow(ctx, stmt, mode);

    // advance to next row
    const next_rc = sqlite.sqlite3_step(stmt);
    try obj.set(ctx.allocator, "__has_row", .{ .bool = next_rc == sqlite.ROW });

    return .{ .array = row };
}

fn stmtFetchAll(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtFetchAll(ctx, obj, args);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtFetchAll(ctx, obj, args);
    const stmt = getStmtPtr(obj) orelse return .{ .bool = false };

    const mode: i64 = if (args.len >= 1 and args[0] == .int) args[0].int else getDefaultFetchMode(obj);

    var result = try ctx.createArray();

    if (mode == 5) {
        try fetchAllAsObjects(ctx, stmt, result, obj);
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return .{ .array = result };
    }

    const has_row_pre = obj.get("__has_row");
    const stepped_pre = obj.get("__stepped");
    const start_with_row = stepped_pre == .bool and stepped_pre.bool and has_row_pre == .bool and has_row_pre.bool;

    // FETCH_CLASS (8): hydrate rows into instances of the given class
    if (mode == 8) {
        var class_name: []const u8 = "stdClass";
        if (args.len >= 2 and args[1] == .string) class_name = args[1].string;
        if (start_with_row) {
            const inst = try fetchRowAsClass(ctx, stmt, class_name);
            try result.append(ctx.allocator, inst);
        }
        var rc = sqlite.sqlite3_step(stmt);
        while (rc == sqlite.ROW) {
            const inst = try fetchRowAsClass(ctx, stmt, class_name);
            try result.append(ctx.allocator, inst);
            rc = sqlite.sqlite3_step(stmt);
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return .{ .array = result };
    }

    // FETCH_KEY_PAIR (12): col 0 = key, col 1 = value
    if (mode == 12) {
        if (start_with_row) {
            const key_v = try columnToValue(ctx, stmt, 0);
            const val_v = try columnToValue(ctx, stmt, 1);
            const ak: PhpArray.Key = switch (key_v) {
                .string => |s| .{ .string = s },
                .int => |n| .{ .int = n },
                else => .{ .int = Value.toInt(key_v) },
            };
            try result.set(ctx.allocator, ak, val_v);
        }
        var rc = sqlite.sqlite3_step(stmt);
        while (rc == sqlite.ROW) {
            const key_v = try columnToValue(ctx, stmt, 0);
            const val_v = try columnToValue(ctx, stmt, 1);
            const ak: PhpArray.Key = switch (key_v) {
                .string => |s| .{ .string = s },
                .int => |n| .{ .int = n },
                else => .{ .int = Value.toInt(key_v) },
            };
            try result.set(ctx.allocator, ak, val_v);
            rc = sqlite.sqlite3_step(stmt);
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return .{ .array = result };
    }

    // FETCH_COLUMN (7): single column from each row, default col 0
    if (mode == 7) {
        if (start_with_row) {
            const val_v = try columnToValue(ctx, stmt, 0);
            try result.append(ctx.allocator, val_v);
        }
        var rc = sqlite.sqlite3_step(stmt);
        while (rc == sqlite.ROW) {
            const val_v = try columnToValue(ctx, stmt, 0);
            try result.append(ctx.allocator, val_v);
            rc = sqlite.sqlite3_step(stmt);
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return .{ .array = result };
    }

    const has_row = obj.get("__has_row");
    const stepped = obj.get("__stepped");

    if (stepped != .bool or !stepped.bool) {
        var rc = sqlite.sqlite3_step(stmt);
        while (rc == sqlite.ROW) {
            const row = try fetchRow(ctx, stmt, mode);
            try result.append(ctx.allocator, .{ .array = row });
            rc = sqlite.sqlite3_step(stmt);
        }
    } else {
        if (has_row == .bool and has_row.bool) {
            const row = try fetchRow(ctx, stmt, mode);
            try result.append(ctx.allocator, .{ .array = row });
            var rc = sqlite.sqlite3_step(stmt);
            while (rc == sqlite.ROW) {
                const next_row = try fetchRow(ctx, stmt, mode);
                try result.append(ctx.allocator, .{ .array = next_row });
                rc = sqlite.sqlite3_step(stmt);
            }
        }
    }

    try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    return .{ .array = result };
}

fn stmtFetchColumn(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtFetchColumn(ctx, obj, args);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtFetchColumn(ctx, obj, args);
    const stmt = getStmtPtr(obj) orelse return .{ .bool = false };

    const col: c_int = if (args.len >= 1 and args[0] == .int) @intCast(args[0].int) else 0;

    const has_row = obj.get("__has_row");
    const stepped = obj.get("__stepped");

    if (stepped != .bool or !stepped.bool) {
        const rc = sqlite.sqlite3_step(stmt);
        if (rc != sqlite.ROW) return .{ .bool = false };
    } else if (has_row != .bool or !has_row.bool) {
        return .{ .bool = false };
    }

    const val = try columnToValue(ctx, stmt, col);

    const next_rc = sqlite.sqlite3_step(stmt);
    try obj.set(ctx.allocator, "__has_row", .{ .bool = next_rc == sqlite.ROW });
    try obj.set(ctx.allocator, "__stepped", .{ .bool = true });

    return val;
}

fn stmtRowCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    _ = getDriver(obj);
    const rc = obj.get("__row_count");
    if (rc == .int) return rc;
    // for SELECT statements, SQLite doesn't provide row count before fetching
    return .{ .int = 0 };
}

fn stmtColumnCount(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtColumnCount(obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtColumnCount(obj);
    const stmt = getStmtPtr(obj) orelse return .{ .int = 0 };
    return .{ .int = sqlite.sqlite3_column_count(stmt) };
}

fn stmtCloseCursor(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtCloseCursor(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtCloseCursor(ctx, obj);
    const stmt = getStmtPtr(obj) orelse return .{ .bool = true };
    _ = sqlite.sqlite3_reset(stmt);
    try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    try obj.set(ctx.allocator, "__stepped", .{ .bool = false });
    return .{ .bool = true };
}

fn stmtSetFetchMode(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const mode: Value = if (args.len >= 1) args[0] else .{ .int = 4 };
    try obj.set(ctx.allocator, "__fetch_mode", mode);
    return .{ .bool = true };
}

fn pdoQuote(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .{ .bool = false };
    var s_buf: [4096]u8 = undefined;
    const v = args[0];
    var input: []const u8 = "";
    var fallback: [32]u8 = undefined;
    switch (v) {
        .string => |s| input = s,
        .int => |n| input = std.fmt.bufPrint(&fallback, "{d}", .{n}) catch return .{ .bool = false },
        .float => |f| input = std.fmt.bufPrint(&fallback, "{d}", .{f}) catch return .{ .bool = false },
        .bool => |b| input = if (b) "1" else "",
        .null => input = "",
        else => return .{ .bool = false },
    }
    // single-quote and double internal quotes per SQL standard
    var w: usize = 0;
    if (w + 1 >= s_buf.len) return .{ .bool = false };
    s_buf[w] = '\''; w += 1;
    for (input) |c| {
        if (c == '\'') {
            if (w + 2 >= s_buf.len) return .{ .bool = false };
            s_buf[w] = '\''; w += 1;
            s_buf[w] = '\''; w += 1;
        } else {
            if (w + 1 >= s_buf.len) return .{ .bool = false };
            s_buf[w] = c; w += 1;
        }
    }
    if (w + 1 >= s_buf.len) return .{ .bool = false };
    s_buf[w] = '\''; w += 1;
    const result = try ctx.createString(s_buf[0..w]);
    return .{ .string = result };
}

fn pdoInTransaction(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    const t = obj.get("__in_transaction");
    return .{ .bool = t == .bool and t.bool };
}

fn pdoGetAvailableDrivers(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .string = "sqlite" });
    try arr.append(ctx.allocator, .{ .string = "mysql" });
    try arr.append(ctx.allocator, .{ .string = "pgsql" });
    return .{ .array = arr };
}

fn pdoErrorCode(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const code = obj.get("__error_code");
    if (code == .string) return code;
    return .{ .string = "00000" };
}

fn stmtErrorCode(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const code = obj.get("__error_code");
    if (code == .string) return code;
    return .{ .string = "00000" };
}

fn stmtErrorInfo(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .null;
    const arr = try ctx.createArray();
    const code = obj.get("__error_code");
    try arr.append(ctx.allocator, if (code == .string) code else .{ .string = "00000" });
    const driver_code = obj.get("__driver_error_code");
    try arr.append(ctx.allocator, if (driver_code == .int) driver_code else .{ .int = 0 });
    const msg = obj.get("__error_message");
    try arr.append(ctx.allocator, if (msg == .string) msg else .null);
    return .{ .array = arr };
}

fn stmtDebugDumpParams(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn stmtGetColumnMeta(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    if (args.len < 1 or args[0] != .int) return .{ .bool = false };
    const stmt = getStmtPtr(obj) orelse return .{ .bool = false };
    const col: c_int = @intCast(args[0].int);
    const arr = try ctx.createArray();
    if (sqlite.sqlite3_column_name(stmt, col)) |np| {
        const n = std.mem.span(np);
        try arr.set(ctx.allocator, .{ .string = "name" }, .{ .string = try ctx.createString(n) });
    }
    return .{ .array = arr };
}

fn stmtNextRowset(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn stmtBindValue(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const obj = getThis(ctx) orelse return .{ .bool = false };
    if (args.len < 2) return .{ .bool = false };
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql") or std.mem.eql(u8, drv, "pgsql")) return .{ .bool = true };
    const stmt = getStmtPtr(obj) orelse return .{ .bool = false };
    const param = args[0];
    const val = args[1];
    const idx: c_int = if (param == .int) @intCast(param.int) else blk: {
        if (param != .string) break :blk @as(c_int, 0);
        const name = param.string;
        break :blk sqlite.sqlite3_bind_parameter_index(stmt, @ptrCast(name.ptr));
    };
    if (idx == 0) return .{ .bool = false };
    const rc = switch (val) {
        .int => sqlite.sqlite3_bind_int64(stmt, idx, val.int),
        .float => sqlite.sqlite3_bind_double(stmt, idx, val.float),
        .string => sqlite.sqlite3_bind_text(stmt, idx, @ptrCast(val.string.ptr), @intCast(val.string.len), null),
        .null => sqlite.sqlite3_bind_null(stmt, idx),
        .bool => sqlite.sqlite3_bind_int64(stmt, idx, if (val.bool) 1 else 0),
        else => sqlite.sqlite3_bind_null(stmt, idx),
    };
    return .{ .bool = rc == sqlite.OK };
}

fn getDefaultFetchMode(obj: *PhpObject) i64 {
    const mode = obj.get("__fetch_mode");
    if (mode == .int) return mode.int;
    return 4; // FETCH_BOTH
}

// helpers

fn fetchRowAsObject(ctx: *NativeContext, stmt: *sqlite.Stmt) !Value {
    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = "stdClass" };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    const col_count = sqlite.sqlite3_column_count(stmt);
    var i: c_int = 0;
    while (i < col_count) : (i += 1) {
        const val = try columnToValue(ctx, stmt, i);
        if (sqlite.sqlite3_column_name(stmt, i)) |name_ptr| {
            const name = std.mem.span(name_ptr);
            try obj.set(ctx.allocator, try ctx.createString(name), val);
        }
    }
    return .{ .object = obj };
}

fn fetchRowAsClass(ctx: *NativeContext, stmt: *sqlite.Stmt, class_name: []const u8) !Value {
    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = class_name };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    if (ctx.vm.classes.contains(class_name)) try ctx.vm.initObjectProperties(obj, class_name);
    const col_count = sqlite.sqlite3_column_count(stmt);
    var i: c_int = 0;
    while (i < col_count) : (i += 1) {
        if (sqlite.sqlite3_column_name(stmt, i)) |name_ptr| {
            const name = std.mem.span(name_ptr);
            const owned = try ctx.createString(name);
            const val = try columnToValue(ctx, stmt, i);
            try obj.set(ctx.allocator, owned, val);
        }
    }
    return .{ .object = obj };
}

fn fetchAllAsObjects(ctx: *NativeContext, stmt: *sqlite.Stmt, result: *PhpArray, obj_parent: *PhpObject) !void {
    const has_row = obj_parent.get("__has_row");
    const stepped = obj_parent.get("__stepped");

    if (stepped != .bool or !stepped.bool) {
        var rc = sqlite.sqlite3_step(stmt);
        while (rc == sqlite.ROW) {
            const row = try fetchRowAsObject(ctx, stmt);
            try result.append(ctx.allocator, row);
            rc = sqlite.sqlite3_step(stmt);
        }
    } else {
        if (has_row == .bool and has_row.bool) {
            const row = try fetchRowAsObject(ctx, stmt);
            try result.append(ctx.allocator, row);
            var rc = sqlite.sqlite3_step(stmt);
            while (rc == sqlite.ROW) {
                const next_row = try fetchRowAsObject(ctx, stmt);
                try result.append(ctx.allocator, next_row);
                rc = sqlite.sqlite3_step(stmt);
            }
        }
    }
}

fn fetchRow(ctx: *NativeContext, stmt: *sqlite.Stmt, mode: i64) !*PhpArray {
    var row = try ctx.createArray();
    const col_count = sqlite.sqlite3_column_count(stmt);
    var i: c_int = 0;
    while (i < col_count) : (i += 1) {
        const val = try columnToValue(ctx, stmt, i);
        // FETCH_NUM (3) or FETCH_BOTH (4)
        if (mode == 3 or mode == 4) {
            try row.append(ctx.allocator, val);
        }
        // FETCH_ASSOC (2) or FETCH_BOTH (4)
        if (mode == 2 or mode == 4) {
            if (sqlite.sqlite3_column_name(stmt, i)) |name_ptr| {
                const name = std.mem.span(name_ptr);
                try row.set(ctx.allocator, .{ .string = try ctx.createString(name) }, val);
            }
        }
    }
    return row;
}

fn columnToValue(ctx: *NativeContext, stmt: *sqlite.Stmt, col: c_int) !Value {
    const col_type = sqlite.sqlite3_column_type(stmt, col);
    return switch (col_type) {
        sqlite.NULL => .null,
        sqlite.INTEGER => .{ .int = sqlite.sqlite3_column_int64(stmt, col) },
        sqlite.FLOAT => .{ .float = sqlite.sqlite3_column_double(stmt, col) },
        sqlite.TEXT, sqlite.BLOB => blk: {
            const text = sqlite.sqlite3_column_text(stmt, col) orelse break :blk Value{ .string = "" };
            const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, col));
            const s = try ctx.createString(text[0..len]);
            break :blk Value{ .string = s };
        },
        else => .null,
    };
}

fn bindParams(ctx: *NativeContext, stmt: *sqlite.Stmt, params: *PhpArray) !void {
    for (params.entries.items) |entry| {
        const idx: c_int = switch (entry.key) {
            .int => |i| @intCast(i + 1),
            .string => |name| blk: {
                // add : prefix if not present
                if (name.len > 0 and name[0] == ':') {
                    const z = try dupeZ(ctx, name);
                    break :blk sqlite.sqlite3_bind_parameter_index(stmt, z);
                }
                var buf: [256]u8 = undefined;
                buf[0] = ':';
                if (name.len < 255) {
                    @memcpy(buf[1 .. name.len + 1], name);
                    buf[name.len + 1] = 0;
                    break :blk sqlite.sqlite3_bind_parameter_index(stmt, buf[0 .. name.len + 1 :0]);
                }
                break :blk @as(c_int, 0);
            },
        };
        if (idx <= 0) continue;

        switch (entry.value) {
            .null => _ = sqlite.sqlite3_bind_null(stmt, idx),
            .bool => |b| _ = sqlite.sqlite3_bind_int64(stmt, idx, if (b) 1 else 0),
            .int => |i| _ = sqlite.sqlite3_bind_int64(stmt, idx, i),
            .float => |f| _ = sqlite.sqlite3_bind_double(stmt, idx, f),
            .string => |s| _ = sqlite.sqlite3_bind_text(stmt, idx, s.ptr, @intCast(s.len), null),
            else => _ = sqlite.sqlite3_bind_null(stmt, idx),
        }
    }
}
