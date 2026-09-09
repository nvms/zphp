const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

fn retainReturned(value: Value) Value {
    if (value == .string) value.string.retain();
    return value;
}

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
    extern "sqlite3" fn sqlite3_free(ptr: ?*anyopaque) callconv(.c) void;
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
    extern "sqlite3" fn sqlite3_errcode(db: *Db) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_stmt_readonly(stmt: *Stmt) callconv(.c) c_int;

    // user-defined SQL function bindings for PDO\Sqlite::createFunction
    pub const Context = opaque {};
    pub const Value_t = opaque {};

    pub const UTF8: c_int = 1;
    pub const DETERMINISTIC: c_int = 0x800;

    extern "sqlite3" fn sqlite3_create_function_v2(
        db: *Db,
        zFunctionName: [*:0]const u8,
        nArg: c_int,
        eTextRep: c_int,
        pApp: ?*anyopaque,
        xFunc: ?*const fn (*Context, c_int, [*]?*Value_t) callconv(.c) void,
        xStep: ?*const fn (*Context, c_int, [*]?*Value_t) callconv(.c) void,
        xFinal: ?*const fn (*Context) callconv(.c) void,
        xDestroy: ?*const fn (?*anyopaque) callconv(.c) void,
    ) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_create_collation_v2(
        db: *Db,
        zName: [*:0]const u8,
        eTextRep: c_int,
        pCtx: ?*anyopaque,
        xCompare: ?*const fn (?*anyopaque, c_int, ?*const anyopaque, c_int, ?*const anyopaque) callconv(.c) c_int,
        xDestroy: ?*const fn (?*anyopaque) callconv(.c) void,
    ) callconv(.c) c_int;

    extern "sqlite3" fn sqlite3_aggregate_context(ctx: *Context, size: c_int) callconv(.c) ?*anyopaque;
    extern "sqlite3" fn sqlite3_user_data(ctx: *Context) callconv(.c) ?*anyopaque;

    extern "sqlite3" fn sqlite3_value_type(v: *Value_t) callconv(.c) c_int;
    extern "sqlite3" fn sqlite3_value_int64(v: *Value_t) callconv(.c) i64;
    extern "sqlite3" fn sqlite3_value_double(v: *Value_t) callconv(.c) f64;
    extern "sqlite3" fn sqlite3_value_text(v: *Value_t) callconv(.c) ?[*:0]const u8;
    extern "sqlite3" fn sqlite3_value_bytes(v: *Value_t) callconv(.c) c_int;

    extern "sqlite3" fn sqlite3_result_null(ctx: *Context) callconv(.c) void;
    extern "sqlite3" fn sqlite3_result_int64(ctx: *Context, v: i64) callconv(.c) void;
    extern "sqlite3" fn sqlite3_result_double(ctx: *Context, v: f64) callconv(.c) void;
    // destructor accepts SQLite's TRANSIENT/STATIC sentinel ints as well as
    // real function pointers; declared as ?*anyopaque to allow the sentinel
    extern "sqlite3" fn sqlite3_result_text(ctx: *Context, v: [*]const u8, n: c_int, destructor: ?*anyopaque) callconv(.c) void;
    extern "sqlite3" fn sqlite3_result_error(ctx: *Context, msg: [*]const u8, n: c_int) callconv(.c) void;

    // SQLITE_TRANSIENT is the magic value -1 cast to a destructor pointer;
    // SQLite recognizes it and copies the buffer before returning
    pub inline fn TRANSIENT() ?*anyopaque {
        return @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
    }
};

// trampoline state passed via sqlite3_create_function_v2's pApp pointer.
// retained on the heap for the lifetime of the function registration.
const UserSqlFn = struct {
    vm: *VM,
    callable: Value,
};

// converts sqlite Value_t args to php Value array, calls the user callable,
// then writes the result back to sqlite. invoked by sqlite on the same
// thread as the original PDO call, so we can safely reach into the VM.
fn sqliteFuncTrampoline(ctx: *sqlite.Context, argc: c_int, argv: [*]?*sqlite.Value_t) callconv(.c) void {
    const user_ptr = sqlite.sqlite3_user_data(ctx) orelse {
        sqlite.sqlite3_result_null(ctx);
        return;
    };
    const state: *UserSqlFn = @ptrCast(@alignCast(user_ptr));

    var arg_buf: [16]Value = undefined;
    const n: usize = @intCast(@max(argc, 0));
    if (n > arg_buf.len) {
        sqlite.sqlite3_result_error(ctx, "too many arguments", 18);
        return;
    }

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const v = argv[i] orelse {
            arg_buf[i] = .null;
            continue;
        };
        arg_buf[i] = switch (sqlite.sqlite3_value_type(v)) {
            sqlite.INTEGER => Value{ .int = sqlite.sqlite3_value_int64(v) },
            sqlite.FLOAT => Value{ .float = sqlite.sqlite3_value_double(v) },
            sqlite.NULL => .null,
            else => blk: {
                const ptr = sqlite.sqlite3_value_text(v) orelse break :blk .{ .string = Value.String.borrowed("") };
                const len: usize = @intCast(@max(sqlite.sqlite3_value_bytes(v), 0));
                const slice = ptr[0..len];
                const owned = state.vm.allocator.dupe(u8, slice) catch break :blk .{ .string = Value.String.borrowed("") };
                state.vm.strings.append(state.vm.allocator, owned) catch {};
                break :blk .{ .string = Value.String.borrowed(owned) };
            },
        };
    }

    var nc = state.vm.makeContext(null);
    const result = nc.invokeCallable(state.callable, arg_buf[0..n]) catch {
        // surface a uniform error to sqlite; the throwing php exception is
        // already on the pending channel for the calling php script to see
        sqlite.sqlite3_result_error(ctx, "callback failed", 15);
        return;
    };

    switch (result) {
        .null => sqlite.sqlite3_result_null(ctx),
        .bool => |b| sqlite.sqlite3_result_int64(ctx, if (b) 1 else 0),
        .int => |n2| sqlite.sqlite3_result_int64(ctx, n2),
        .float => |f| sqlite.sqlite3_result_double(ctx, f),
        .string => |s| sqlite.sqlite3_result_text(ctx, s.bytes().ptr, @intCast(s.bytes().len), sqlite.TRANSIENT()),
        else => sqlite.sqlite3_result_null(ctx),
    }
}

fn sqliteFuncDestroy(p: ?*anyopaque) callconv(.c) void {
    if (p) |ptr| {
        const state: *UserSqlFn = @ptrCast(@alignCast(ptr));
        state.vm.releaseValue(state.callable);
        state.vm.allocator.destroy(state);
    }
}

fn sqliteCollationTrampoline(p: ?*anyopaque, alen: c_int, aptr: ?*const anyopaque, blen: c_int, bptr: ?*const anyopaque) callconv(.c) c_int {
    const ptr = p orelse return 0;
    const state: *UserSqlFn = @ptrCast(@alignCast(ptr));
    const a_slice: []const u8 = if (aptr) |x|
        @as([*]const u8, @ptrCast(x))[0..@intCast(@max(alen, 0))]
    else
        "";
    const b_slice: []const u8 = if (bptr) |x|
        @as([*]const u8, @ptrCast(x))[0..@intCast(@max(blen, 0))]
    else
        "";
    const a_owned = state.vm.allocator.dupe(u8, a_slice) catch return 0;
    state.vm.strings.append(state.vm.allocator, a_owned) catch {};
    const b_owned = state.vm.allocator.dupe(u8, b_slice) catch return 0;
    state.vm.strings.append(state.vm.allocator, b_owned) catch {};

    var nc = state.vm.makeContext(null);
    const result = nc.invokeCallable(state.callable, &.{ .{ .string = Value.String.borrowed(a_owned) }, .{ .string = Value.String.borrowed(b_owned) } }) catch return 0;
    return switch (result) {
        .int => |n| if (n < 0) @as(c_int, -1) else if (n > 0) @as(c_int, 1) else @as(c_int, 0),
        else => 0,
    };
}

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

// SQLite callbacks cannot unwind through C. Re-throw their pending PHP
// exception at every stepping boundary, including fetch loops and silent mode.
fn stepSqlite(ctx: *NativeContext, stmt: *sqlite.Stmt) RuntimeError!c_int {
    const rc = sqlite.sqlite3_step(stmt);
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    return rc;
}

// build the SQLSTATE-prefixed message PHP's PDO uses for sqlite errors:
// "SQLSTATE[HY000]: General error: <sqlite_errcode> <sqlite_errmsg>"
fn pdoSqlMsg(ctx: *NativeContext, db: *sqlite.Db, raw: []const u8) ![]const u8 {
    const code = sqlite.sqlite3_errcode(db);
    const m = try std.fmt.allocPrint(ctx.allocator, "SQLSTATE[HY000]: General error: {d} {s}", .{ code, raw });
    try ctx.strings.append(ctx.allocator, m);
    return m;
}

pub fn throwPdo(ctx: *NativeContext, msg: []const u8) RuntimeError!NativeResult {
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    // honor ATTR_ERRMODE: silent (0) returns false, warning (1) returns false,
    // exception (2) throws PDOException. default in PHP 8 is exception, but for
    // backward-compat zphp defaults the construct path to exception too
    if (ctx.vm.currentFrame().vars.get("$this")) |this_v| {
        if (this_v == .object) {
            const obj = this_v.object;
            try obj.set(ctx.allocator, "__error_code", .{ .string = Value.String.borrowed("HY000") });
            const owned = try ctx.createString(msg);
            try obj.set(ctx.allocator, "__error_message", .{ .string = Value.String.borrowed(owned) });
            const mode = obj.get("__errmode");
            const m: i64 = if (mode == .int) mode.int else 2;
            if (m != 2) return NativeResult.scalar(.{ .bool = false });
        }
    }
    _ = try ctx.vm.throwBuiltinException("PDOException", msg);
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
    var pdo_def = ClassDef{ .name = "PDO", .native_cleanup = cleanupConnection };
    try pdo_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try pdo_def.methods.put(a, "exec", .{ .name = "exec", .arity = 1 });
    try pdo_def.methods.put(a, "query", .{ .name = "query", .arity = 1 });
    try pdo_def.methods.put(a, "prepare", .{ .name = "prepare", .arity = 1 });
    try pdo_def.methods.put(a, "lastInsertId", .{ .name = "lastInsertId", .arity = 0 });
    try pdo_def.methods.put(a, "beginTransaction", .{ .name = "beginTransaction", .arity = 0 });
    try pdo_def.methods.put(a, "commit", .{ .name = "commit", .arity = 0 });
    try pdo_def.methods.put(a, "rollBack", .{ .name = "rollBack", .arity = 0 });
    try pdo_def.methods.put(a, "rollback", .{ .name = "rollback", .arity = 0 });
    try pdo_def.methods.put(a, "errorInfo", .{ .name = "errorInfo", .arity = 0 });
    try pdo_def.methods.put(a, "errorCode", .{ .name = "errorCode", .arity = 0 });
    try pdo_def.methods.put(a, "setAttribute", .{ .name = "setAttribute", .arity = 2 });
    try pdo_def.methods.put(a, "getAttribute", .{ .name = "getAttribute", .arity = 1 });
    try pdo_def.methods.put(a, "quote", .{ .name = "quote", .arity = 1 });
    try pdo_def.methods.put(a, "inTransaction", .{ .name = "inTransaction", .arity = 0 });
    try pdo_def.methods.put(a, "getAvailableDrivers", .{ .name = "getAvailableDrivers", .arity = 0, .is_static = true });
    // legacy aliases (PHP exposes these directly on PDO when the driver is sqlite)
    try pdo_def.methods.put(a, "sqliteCreateFunction", .{ .name = "sqliteCreateFunction", .arity = 2 });
    try pdo_def.methods.put(a, "sqliteCreateAggregate", .{ .name = "sqliteCreateAggregate", .arity = 3 });
    try pdo_def.methods.put(a, "sqliteCreateCollation", .{ .name = "sqliteCreateCollation", .arity = 2 });

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
    try pdo_def.static_props.put(a, "FETCH_INTO", .{ .int = 9 });
    try pdo_def.static_props.put(a, "FETCH_NAMED", .{ .int = 11 });
    try pdo_def.static_props.put(a, "FETCH_FUNC", .{ .int = 10 });
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
    try pdo_def.static_props.put(a, "PARAM_STMT", .{ .int = 4 });
    try pdo_def.static_props.put(a, "PARAM_INPUT_OUTPUT", .{ .int = 2147483648 });
    try pdo_def.static_props.put(a, "PARAM_STR_CHAR", .{ .int = 536870912 });
    try pdo_def.static_props.put(a, "PARAM_STR_NATL", .{ .int = 1073741824 });
    // remaining standard PDO::ATTR_* attributes (zphp routes all drivers
    // through one PDO class; frameworks reference the whole family). values
    // match php-src ext/pdo
    try pdo_def.static_props.put(a, "ATTR_PREFETCH", .{ .int = 1 });
    try pdo_def.static_props.put(a, "ATTR_TIMEOUT", .{ .int = 2 });
    try pdo_def.static_props.put(a, "ATTR_SERVER_INFO", .{ .int = 6 });
    try pdo_def.static_props.put(a, "ATTR_CONNECTION_STATUS", .{ .int = 7 });
    try pdo_def.static_props.put(a, "ATTR_CURSOR_NAME", .{ .int = 9 });
    try pdo_def.static_props.put(a, "ATTR_CURSOR", .{ .int = 10 });
    try pdo_def.static_props.put(a, "ATTR_ORACLE_NULLS", .{ .int = 11 });
    try pdo_def.static_props.put(a, "ATTR_STATEMENT_CLASS", .{ .int = 13 });
    try pdo_def.static_props.put(a, "ATTR_FETCH_TABLE_NAMES", .{ .int = 14 });
    try pdo_def.static_props.put(a, "ATTR_FETCH_CATALOG_NAMES", .{ .int = 15 });
    try pdo_def.static_props.put(a, "ATTR_STRINGIFY_FETCHES", .{ .int = 17 });
    try pdo_def.static_props.put(a, "ATTR_MAX_COLUMN_LEN", .{ .int = 18 });
    try pdo_def.static_props.put(a, "ATTR_DEFAULT_STR_PARAM", .{ .int = 21 });
    try pdo_def.static_props.put(a, "CURSOR_FWDONLY", .{ .int = 0 });
    try pdo_def.static_props.put(a, "CURSOR_SCROLL", .{ .int = 1 });
    try pdo_def.static_props.put(a, "NULL_NATURAL", .{ .int = 0 });
    try pdo_def.static_props.put(a, "NULL_EMPTY_STRING", .{ .int = 1 });
    try pdo_def.static_props.put(a, "NULL_TO_STRING", .{ .int = 2 });
    try pdo_def.static_props.put(a, "FETCH_ORI_NEXT", .{ .int = 0 });
    try pdo_def.static_props.put(a, "FETCH_ORI_PRIOR", .{ .int = 1 });
    try pdo_def.static_props.put(a, "FETCH_ORI_FIRST", .{ .int = 2 });
    try pdo_def.static_props.put(a, "FETCH_ORI_LAST", .{ .int = 3 });
    try pdo_def.static_props.put(a, "FETCH_ORI_ABS", .{ .int = 4 });
    try pdo_def.static_props.put(a, "FETCH_ORI_REL", .{ .int = 5 });
    // pdo_mysql driver-specific attributes. zphp's PDO dispatches through one
    // class regardless of driver, so register the full family - frameworks
    // reference them in connection config (e.g. Laravel's mysql options) even
    // when a different driver is active. values match PHP 8.x pdo_mysql
    try pdo_def.static_props.put(a, "MYSQL_ATTR_USE_BUFFERED_QUERY", .{ .int = 1000 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_LOCAL_INFILE", .{ .int = 1001 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_INIT_COMMAND", .{ .int = 1002 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_COMPRESS", .{ .int = 1003 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_DIRECT_QUERY", .{ .int = 20 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_FOUND_ROWS", .{ .int = 1004 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_IGNORE_SPACE", .{ .int = 1005 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_SSL_KEY", .{ .int = 1006 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_SSL_CERT", .{ .int = 1007 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_SSL_CA", .{ .int = 1008 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_SSL_CAPATH", .{ .int = 1009 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_SSL_CIPHER", .{ .int = 1010 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_SERVER_PUBLIC_KEY", .{ .int = 1011 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_MULTI_STATEMENTS", .{ .int = 1012 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_SSL_VERIFY_SERVER_CERT", .{ .int = 1013 });
    try pdo_def.static_props.put(a, "MYSQL_ATTR_LOCAL_INFILE_DIRECTORY", .{ .int = 1014 });

    try vm.classes.put(a, "PDO", pdo_def);

    // PHP 8.4 introduced PDO subclass drivers in the PDO\ namespace. zphp
    // dispatches through a single PDO class, but register the names so
    // `new PDO\Sqlite(...)` / `instanceof PDO\Sqlite` / autoloaders don't
    // hit "class not found" (used by WP's sqlite-database-integration)
    inline for (.{ "Sqlite", "SQLite", "Mysql", "MySql", "Pgsql", "PgSql", "Odbc", "ODBC", "Firebird", "Dblib" }) |driver| {
        const fqn = "PDO\\" ++ driver;
        var sub_def = ClassDef{ .name = fqn, .parent = "PDO", .native_cleanup = cleanupConnection };
        try sub_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
        // Sqlite-specific extension methods (user-defined SQL function /
        // aggregate / collation hooks). Backed by SQLite callbacks so frameworks
        // that conditionally call them (WordPress's sqlite-database-integration)
        // can register real SQL callbacks.
        try sub_def.methods.put(a, "createFunction", .{ .name = "createFunction", .arity = 2 });
        try sub_def.methods.put(a, "createAggregate", .{ .name = "createAggregate", .arity = 3 });
        try sub_def.methods.put(a, "createCollation", .{ .name = "createCollation", .arity = 2 });
        try vm.classes.put(a, fqn, sub_def);
        try vm.native_fns.put(a, fqn ++ "::__construct", pdoConstruct);
        try vm.native_fns.put(a, fqn ++ "::createFunction", pdoSqliteCreateFunction);
        try vm.native_fns.put(a, fqn ++ "::createAggregate", pdoSqliteCreateAggregate);
        try vm.native_fns.put(a, fqn ++ "::createCollation", pdoSqliteCreateCollation);
    }

    // PHP's documented spelling; class construction currently uses exact keys.
    var sqlite_alias = ClassDef{ .name = "Pdo\\Sqlite", .parent = "PDO\\Sqlite", .native_cleanup = cleanupConnection };
    try sqlite_alias.methods.put(a, "__construct", .{ .name = "__construct", .arity = 3 });
    try vm.classes.put(a, "Pdo\\Sqlite", sqlite_alias);
    try vm.native_fns.put(a, "Pdo\\Sqlite::__construct", pdoConstruct);

    try vm.native_fns.put(a, "PDO::__construct", pdoConstruct);
    try vm.native_fns.put(a, "PDO::connect", pdoConnect);
    try vm.native_fns.put(a, "PDO::exec", pdoExec);
    try vm.native_fns.put(a, "PDO::query", pdoQuery);
    try vm.native_fns.put(a, "PDO::quote", pdoQuote);
    try vm.native_fns.put(a, "PDO::inTransaction", pdoInTransaction);
    try vm.native_fns.put(a, "PDO::getAvailableDrivers", pdoGetAvailableDrivers);
    try vm.native_fns.put(a, "PDO::sqliteCreateFunction", pdoSqliteCreateFunction);
    try vm.native_fns.put(a, "PDO::sqliteCreateAggregate", pdoSqliteCreateAggregate);
    try vm.native_fns.put(a, "PDO::sqliteCreateCollation", pdoSqliteCreateCollation);
    try vm.native_fns.put(a, "PDO::errorCode", pdoErrorCode);
    try vm.native_fns.put(a, "PDO::prepare", pdoPrepare);
    try vm.native_fns.put(a, "PDO::lastInsertId", pdoLastInsertId);
    try vm.native_fns.put(a, "PDO::beginTransaction", pdoBeginTransaction);
    try vm.native_fns.put(a, "PDO::commit", pdoCommit);
    try vm.native_fns.put(a, "PDO::rollBack", pdoRollBack);
    try vm.native_fns.put(a, "PDO::rollback", pdoRollBack);
    try vm.native_fns.put(a, "PDO::errorInfo", pdoErrorInfo);
    try vm.native_fns.put(a, "PDO::setAttribute", pdoSetAttribute);
    try vm.native_fns.put(a, "PDO::getAttribute", pdoGetAttribute);

    var stmt_def = ClassDef{ .name = "PDOStatement", .native_cleanup = cleanupStatement };
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

fn stmtIterRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__iter_key", .{ .int = 0 });
    // fetch the first row
    const row = (try stmtFetch(ctx, &.{})).value;
    try obj.set(ctx.allocator, "__iter_current", row);
    return NativeResult.scalar(.null);
}

fn stmtIterCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__iter_current"));
}

fn stmtIterKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.share(obj.get("__iter_key"));
}

fn stmtIterNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cur_key = Value.toInt(obj.get("__iter_key"));
    try obj.set(ctx.allocator, "__iter_key", .{ .int = cur_key + 1 });
    const row = (try stmtFetch(ctx, &.{})).value;
    try obj.set(ctx.allocator, "__iter_current", row);
    return NativeResult.scalar(.null);
}

fn stmtIterValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const cur = obj.get("__iter_current");
    // FETCH_CLASS / FETCH_OBJ produce objects; FETCH_ASSOC etc produce arrays.
    // either type is a valid row - only null/false means no more rows
    return NativeResult.scalar(.{ .bool = cur == .array or cur == .object });
}

fn stmtFetchObject(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const row = (try stmtFetch(ctx, &.{.{ .int = 2 }})).value; // FETCH_ASSOC
    if (row != .array) return NativeResult.scalar(.{ .bool = false });
    var class_name: []const u8 = "stdClass";
    if (args.len >= 1 and args[0] == .string) class_name = args[0].string.bytes();
    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = class_name };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    if (ctx.vm.classes.contains(class_name)) {
        try ctx.vm.initObjectProperties(obj, class_name);
    }
    for (row.array.entries.items) |entry| {
        if (entry.key == .string) try obj.set(ctx.allocator, entry.key.string.bytes(), entry.value);
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn cleanupStatement(obj: *PhpObject) bool {
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) {
        pdo_mysql.cleanupStatement(obj);
    } else if (std.mem.eql(u8, drv, "pgsql")) {
        pdo_pgsql.cleanupStatement(obj);
    } else if (getStmtPtr(obj)) |stmt| {
        _ = sqlite.sqlite3_finalize(stmt);
    }
    if (obj.properties.getPtr("__stmt_ptr")) |slot| slot.* = .{ .int = 0 };
    return true;
}

fn cleanupConnection(obj: *PhpObject) bool {
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) {
        pdo_mysql.cleanupConnection(obj);
    } else if (std.mem.eql(u8, drv, "pgsql")) {
        pdo_pgsql.cleanupConnection(obj);
    } else if (getDbPtr(obj)) |db| {
        // v2 defers destruction until outstanding statements are finalized;
        // sqlite3_close would return BUSY and leak the connection/registrations.
        _ = sqlite.sqlite3_close_v2(db);
    }
    if (obj.properties.getPtr("__db_ptr")) |slot| slot.* = .{ .int = 0 };
    return true;
}

pub fn cleanupResources(objects: std.ArrayListUnmanaged(*PhpObject)) void {
    // finalize statements first, then close databases. the obj is being torn down
    // right after this so we don't need to clear the pointer fields in the
    // property map (which would require the VM allocator to grow the bucket).
    for (objects.items) |obj| {
        if (obj.pooled) continue;
        if (std.mem.eql(u8, obj.class_name, "PDOStatement")) {
            const drv = getDriver(obj);
            if (std.mem.eql(u8, drv, "mysql")) {
                pdo_mysql.cleanupStatement(obj);
            } else if (std.mem.eql(u8, drv, "pgsql")) {
                pdo_pgsql.cleanupStatement(obj);
            } else {
                if (getStmtPtr(obj)) |stmt| _ = sqlite.sqlite3_finalize(stmt);
            }
        }
    }
    for (objects.items) |obj| {
        if (obj.pooled) continue;
        // PDO base class plus the PHP 8.4 driver subclasses live under PDO\
        if (std.mem.eql(u8, obj.class_name, "PDO") or (obj.class_name.len >= 4 and std.ascii.eqlIgnoreCase(obj.class_name[0..4], "PDO\\"))) {
            const drv = getDriver(obj);
            if (std.mem.eql(u8, drv, "mysql")) {
                pdo_mysql.cleanupConnection(obj);
            } else if (std.mem.eql(u8, drv, "pgsql")) {
                pdo_pgsql.cleanupConnection(obj);
            } else {
                if (getDbPtr(obj)) |db| _ = sqlite.sqlite3_close_v2(db);
            }
        }
    }
}

// PDO methods

const pdo_mysql = @import("pdo_mysql.zig");
const pdo_pgsql = @import("pdo_pgsql.zig");

fn getDriver(obj: *PhpObject) []const u8 {
    const v = obj.get("__driver");
    if (v == .string) return v.string.bytes();
    return "sqlite";
}

fn pdoConnect(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
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
    return NativeResult.borrowed(.{ .object = obj });
}

// PDO\Sqlite::createFunction(string $name, callable $callback, int $numArgs = -1)
// registers a PHP callable as a SQLite scalar function. wires the trampoline
// so SQLite actually invokes the PHP code on every call.
fn pdoSqliteCreateFunction(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    if (args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const db = getDbPtr(this) orelse return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();
    const num_args: c_int = if (args.len >= 3 and args[2] == .int) @intCast(args[2].int) else -1;

    const state = try ctx.vm.allocator.create(UserSqlFn);
    state.* = .{ .vm = ctx.vm, .callable = args[1] };
    VM.retainValue(state.callable);

    // dupe with manual null terminator so the slice we hand to vm.strings has
    // matching len for free(). dupeZ returns a [:0] slice whose .len excludes
    // the sentinel byte, which trips gpa's size-tracking on later free
    const name_buf = try ctx.allocator.alloc(u8, name.len + 1);
    @memcpy(name_buf[0..name.len], name);
    name_buf[name.len] = 0;
    try ctx.vm.strings.append(ctx.allocator, name_buf);

    const rc = sqlite.sqlite3_create_function_v2(
        db,
        @ptrCast(name_buf.ptr),
        num_args,
        sqlite.UTF8,
        @ptrCast(state),
        sqliteFuncTrampoline,
        null,
        null,
        sqliteFuncDestroy,
    );
    if (rc != 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

// SQLite owns registrations; each aggregate group owns an independent PHP
// accumulator until xFinal (also called on reset/finalize after a failed step).
const UserSqlAggregate = struct { vm: *VM, step: Value, final: Value };
const AggregateGroup = struct { value: Value = .null, row: i64 = 0, failed: bool = false };

fn aggregateDestroy(p: ?*anyopaque) callconv(.c) void {
    const registration: *UserSqlAggregate = @ptrCast(@alignCast(p orelse return));
    registration.vm.releaseValue(registration.step);
    registration.vm.releaseValue(registration.final);
    registration.vm.allocator.destroy(registration);
}

fn aggregateGroup(ctx: *sqlite.Context, vm: *VM) ?*AggregateGroup {
    // SQLite zero-initializes this pointer slot, not a tagged Zig Value.
    const slot: *?*AggregateGroup = @ptrCast(@alignCast(sqlite.sqlite3_aggregate_context(ctx, @sizeOf(?*AggregateGroup)) orelse return null));
    if (slot.* == null) {
        const group = vm.allocator.create(AggregateGroup) catch return null;
        group.* = .{};
        slot.* = group;
    }
    return slot.*;
}

fn aggregateStep(ctx: *sqlite.Context, argc: c_int, argv: [*]?*sqlite.Value_t) callconv(.c) void {
    const reg: *UserSqlAggregate = @ptrCast(@alignCast(sqlite.sqlite3_user_data(ctx).?));
    const group = aggregateGroup(ctx, reg.vm) orelse {
        sqlite.sqlite3_result_error(ctx, "out of memory", 13);
        return;
    };
    if (group.failed) return;
    const n: usize = @intCast(@max(argc, 0));
    const args = reg.vm.allocator.alloc(Value, n + 2) catch {
        group.failed = true;
        sqlite.sqlite3_result_error(ctx, "out of memory", 13);
        return;
    };
    defer reg.vm.allocator.free(args);
    group.row += 1;
    args[0] = group.value;
    args[1] = .{ .int = group.row };
    var nc = reg.vm.makeContext(null);
    for (args[2..], 0..) |*arg, i| {
        const v = argv[i] orelse {
            arg.* = .null;
            continue;
        };
        arg.* = switch (sqlite.sqlite3_value_type(v)) {
            sqlite.INTEGER => .{ .int = sqlite.sqlite3_value_int64(v) },
            sqlite.FLOAT => .{ .float = sqlite.sqlite3_value_double(v) },
            sqlite.NULL => .null,
            else => blk: {
                const ptr = sqlite.sqlite3_value_text(v) orelse break :blk .null;
                const text = nc.createString(ptr[0..@intCast(@max(sqlite.sqlite3_value_bytes(v), 0))]) catch {
                    group.failed = true;
                    sqlite.sqlite3_result_error(ctx, "out of memory", 13);
                    return;
                };
                break :blk .{ .string = Value.String.borrowed(text) };
            },
        };
    }
    const result = nc.invokeCallable(reg.step, args) catch {
        group.failed = true;
        sqlite.sqlite3_result_error(ctx, "callback failed", 15);
        return;
    };
    // Call results are borrowed-deferred: pin before releasing the old context.
    VM.retainValue(result);
    reg.vm.releaseValue(group.value);
    group.value = result;
}

fn aggregateFinal(ctx: *sqlite.Context) callconv(.c) void {
    const reg: *UserSqlAggregate = @ptrCast(@alignCast(sqlite.sqlite3_user_data(ctx).?));
    const group = aggregateGroup(ctx, reg.vm) orelse {
        sqlite.sqlite3_result_error(ctx, "out of memory", 13);
        return;
    };
    defer {
        reg.vm.releaseValue(group.value);
        reg.vm.allocator.destroy(group);
        const slot: *?*AggregateGroup = @ptrCast(@alignCast(sqlite.sqlite3_aggregate_context(ctx, 0).?));
        slot.* = null;
    }
    if (group.failed or reg.vm.pending_exception != null) return;
    var nc = reg.vm.makeContext(null);
    // PHP increments the row counter for final too, including empty groups.
    const result = nc.invokeCallable(reg.final, &.{ group.value, .{ .int = group.row + 1 } }) catch {
        sqlite.sqlite3_result_error(ctx, "callback failed", 15);
        return;
    };
    VM.retainValue(result);
    defer reg.vm.releaseValue(result);
    switch (result) {
        .null => sqlite.sqlite3_result_null(ctx),
        .int => |v| sqlite.sqlite3_result_int64(ctx, v),
        .float => |v| sqlite.sqlite3_result_double(ctx, v),
        .object => |obj| {
            const text = reg.vm.objectToString(obj) catch {
                sqlite.sqlite3_result_error(ctx, "callback result conversion failed", 33);
                return;
            };
            sqlite.sqlite3_result_text(ctx, text.ptr, @intCast(text.len), sqlite.TRANSIENT());
        },
        else => {
            var buffer: std.ArrayListUnmanaged(u8) = .empty;
            defer buffer.deinit(reg.vm.allocator);
            result.format(&buffer, reg.vm.allocator) catch {
                sqlite.sqlite3_result_error(ctx, "callback result conversion failed", 33);
                return;
            };
            const text = buffer.items;
            sqlite.sqlite3_result_text(ctx, text.ptr, @intCast(text.len), sqlite.TRANSIENT());
        },
    }
}

fn pdoSqliteCreateAggregate(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 3 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    for (args[1..3], 2..) |callback, position| {
        const valid = try ctx.callFunction("is_callable", &.{callback});
        if (!valid.isTruthy()) {
            const message = try std.fmt.allocPrint(ctx.allocator, "PDO::sqliteCreateAggregate(): Argument #{d} (${s}) must be a valid callback", .{ position, if (position == 2) "step" else "finalize" });
            defer ctx.allocator.free(message);
            _ = try ctx.vm.throwBuiltinException("TypeError", message);
            return error.RuntimeError;
        }
    }
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const db = getDbPtr(this) orelse return NativeResult.scalar(.{ .bool = false });
    const count = if (args.len > 3) args[3].toInt() else -1;
    const num_args = std.math.cast(c_int, count) orelse return NativeResult.scalar(.{ .bool = false });
    const name = try ctx.allocator.dupeZ(u8, args[0].string.bytes());
    defer ctx.allocator.free(name);
    const reg = try ctx.allocator.create(UserSqlAggregate);
    reg.* = .{ .vm = ctx.vm, .step = args[1], .final = args[2] };
    VM.retainValue(reg.step);
    VM.retainValue(reg.final);
    // v2 invokes the destructor even when registration fails.
    const rc = sqlite.sqlite3_create_function_v2(db, name, num_args, sqlite.UTF8, reg, null, aggregateStep, aggregateFinal, aggregateDestroy);
    return NativeResult.scalar(.{ .bool = rc == sqlite.OK });
}

fn pdoSqliteCreateCollation(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    if (args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const db = getDbPtr(this) orelse return NativeResult.scalar(.{ .bool = false });
    const name = args[0].string.bytes();

    const state = try ctx.vm.allocator.create(UserSqlFn);
    state.* = .{ .vm = ctx.vm, .callable = args[1] };
    VM.retainValue(state.callable);

    const name_buf = try ctx.allocator.alloc(u8, name.len + 1);
    @memcpy(name_buf[0..name.len], name);
    name_buf[name.len] = 0;
    try ctx.vm.strings.append(ctx.allocator, name_buf);

    const rc = sqlite.sqlite3_create_collation_v2(db, @ptrCast(name_buf.ptr), sqlite.UTF8, @ptrCast(state), sqliteCollationTrampoline, sqliteFuncDestroy);
    if (rc != 0) {
        sqliteFuncDestroy(state);
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn pdoConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return throwPdo(ctx, "PDO::__construct() expects a DSN string");

    const dsn = args[0].string.bytes();
    const colon = std.mem.indexOf(u8, dsn, ":") orelse return throwPdo(ctx, "Invalid DSN: missing driver prefix");
    const driver = dsn[0..colon];
    const rest = dsn[colon + 1 ..];

    try obj.set(ctx.allocator, "__driver", .{ .string = Value.String.borrowed(try ctx.createString(driver)) });

    if (std.mem.eql(u8, driver, "sqlite")) {
        const path_z = try dupeZ(ctx, rest);
        var db: ?*sqlite.Db = null;
        const rc = sqlite.sqlite3_open(path_z, &db);
        if (rc != sqlite.OK or db == null) return throwPdo(ctx, "Failed to open database");
        try obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(db.?)) });
        try applyOptionsArray(ctx, obj, args);
        return NativeResult.scalar(.null);
    }

    if (std.mem.eql(u8, driver, "mysql")) {
        const r = try pdo_mysql.connect(ctx, obj, rest, args);
        try applyOptionsArray(ctx, obj, args);
        return r;
    }
    if (std.mem.eql(u8, driver, "pgsql")) {
        const r = try pdo_pgsql.connect(ctx, obj, rest, args);
        try applyOptionsArray(ctx, obj, args);
        return r;
    }

    return throwPdo(ctx, "Unsupported PDO driver");
}

fn applyOptionsArray(ctx: *NativeContext, obj: *PhpObject, args: []const Value) !void {
    if (args.len < 4 or args[3] != .array) return;
    const opts = args[3].array;
    for (opts.entries.items) |entry| {
        if (entry.key != .int) continue;
        const k = entry.key.int;
        if (k == 3) { // ATTR_ERRMODE
            try obj.set(ctx.allocator, "__errmode", entry.value);
        } else if (k == 19) { // ATTR_DEFAULT_FETCH_MODE
            try obj.set(ctx.allocator, "__default_fetch_mode", entry.value);
        }
    }
}

fn pdoExec(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return throwPdo(ctx, "PDO::exec() expects a SQL string");
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.exec(ctx, obj, args[0].string.bytes());
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.exec(ctx, obj, args[0].string.bytes());
    const db = getDbPtr(obj) orelse return throwPdo(ctx, "Database not connected");
    const sql_z = try dupeZ(ctx, args[0].string.bytes());
    var errmsg: ?[*:0]u8 = null;
    const rc = sqlite.sqlite3_exec(db, sql_z, null, null, @ptrCast(&errmsg));
    defer if (errmsg) |message| sqlite.sqlite3_free(message);
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    if (rc != sqlite.OK) {
        const raw = if (errmsg) |e| std.mem.span(e) else "SQL execution error";
        const result = try throwPdo(ctx, try pdoSqlMsg(ctx, db, raw));
        if (result.value == .bool and !result.value.bool) return NativeResult.scalar(.{ .bool = false });
        return result;
    }
    return NativeResult.scalar(.{ .int = sqlite.sqlite3_changes(db) });
}

fn pdoQuery(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return throwPdo(ctx, "PDO::query() expects a SQL string");
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.query(ctx, obj, args[0].string.bytes());
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.query(ctx, obj, args[0].string.bytes());
    const db = getDbPtr(obj) orelse return throwPdo(ctx, "Database not connected");

    const sql_z = try dupeZ(ctx, args[0].string.bytes());
    var stmt_ptr: ?*sqlite.Stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(db, sql_z, -1, &stmt_ptr, null);
    if (rc != sqlite.OK or stmt_ptr == null) {
        const msg = std.mem.span(sqlite.sqlite3_errmsg(db));
        return throwPdo(ctx, try pdoSqlMsg(ctx, db, msg));
    }

    const stmt_obj = try ctx.createObject("PDOStatement");
    try stmt_obj.set(ctx.allocator, "__stmt_ptr", .{ .int = @intCast(@intFromPtr(stmt_ptr.?)) });
    try stmt_obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(db)) });
    try stmt_obj.set(ctx.allocator, "__pdo", .{ .object = obj });
    // step once to position on first row
    const step_rc = try stepSqlite(ctx, stmt_ptr.?);
    if (step_rc != sqlite.ROW and step_rc != sqlite.DONE)
        return throwPdo(ctx, try pdoSqlMsg(ctx, db, std.mem.span(sqlite.sqlite3_errmsg(db))));
    try stmt_obj.set(ctx.allocator, "__has_row", .{ .bool = step_rc == sqlite.ROW });
    try stmt_obj.set(ctx.allocator, "__stepped", .{ .bool = true });

    return NativeResult.borrowed(.{ .object = stmt_obj });
}

fn pdoPrepare(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return throwPdo(ctx, "PDO::prepare() expects a SQL string");
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.prepare(ctx, obj, args[0].string.bytes());
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.prepare(ctx, obj, args[0].string.bytes());
    const db = getDbPtr(obj) orelse return throwPdo(ctx, "Database not connected");

    const sql_z = try dupeZ(ctx, args[0].string.bytes());
    var stmt_ptr: ?*sqlite.Stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(db, sql_z, -1, &stmt_ptr, null);
    if (rc != sqlite.OK or stmt_ptr == null) {
        const msg = std.mem.span(sqlite.sqlite3_errmsg(db));
        return throwPdo(ctx, try pdoSqlMsg(ctx, db, msg));
    }

    const stmt_obj = try ctx.createObject("PDOStatement");
    try stmt_obj.set(ctx.allocator, "__stmt_ptr", .{ .int = @intCast(@intFromPtr(stmt_ptr.?)) });
    try stmt_obj.set(ctx.allocator, "__db_ptr", .{ .int = @intCast(@intFromPtr(db)) });
    try stmt_obj.set(ctx.allocator, "__pdo", .{ .object = obj });
    try stmt_obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    try stmt_obj.set(ctx.allocator, "__stepped", .{ .bool = false });

    return NativeResult.borrowed(.{ .object = stmt_obj });
}

fn pdoLastInsertId(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.lastInsertId(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.lastInsertId(ctx, obj);
    const db = getDbPtr(obj) orelse return NativeResult.literal("0");
    const id = sqlite.sqlite3_last_insert_rowid(db);
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{id}) catch "0";
    return try NativeResult.copyString(ctx.allocator, s);
}

fn pdoBeginTransaction(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const in_tx = obj.get("__in_transaction");
    if (in_tx == .bool and in_tx.bool) {
        try ctx.vm.setPendingException("PDOException", "There is already an active transaction");
        return error.RuntimeError;
    }
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.beginTransaction(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.beginTransaction(ctx, obj);
    const db = getDbPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const rc = sqlite.sqlite3_exec(db, "BEGIN", null, null, null);
    if (rc == sqlite.OK) try obj.set(ctx.allocator, "__in_transaction", .{ .bool = true });
    return NativeResult.scalar(.{ .bool = rc == sqlite.OK });
}

fn pdoCommit(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.commit(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.commit(ctx, obj);
    const db = getDbPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const rc = sqlite.sqlite3_exec(db, "COMMIT", null, null, null);
    if (rc == sqlite.OK) try obj.set(ctx.allocator, "__in_transaction", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = rc == sqlite.OK });
}

fn pdoRollBack(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.rollBack(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.rollBack(ctx, obj);
    const db = getDbPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const rc = sqlite.sqlite3_exec(db, "ROLLBACK", null, null, null);
    if (rc == sqlite.OK) try obj.set(ctx.allocator, "__in_transaction", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = rc == sqlite.OK });
}

fn pdoErrorInfo(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.errorInfo(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.errorInfo(ctx, obj);
    const db = getDbPtr(obj) orelse return NativeResult.scalar(.null);
    var arr = try ctx.createArray();
    const msg = std.mem.span(sqlite.sqlite3_errmsg(db));
    const has_err = !std.mem.eql(u8, msg, "not an error") and msg.len > 0;
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(if (has_err) "HY000" else "00000") });
    if (has_err) {
        try arr.append(ctx.allocator, .{ .int = sqlite.sqlite3_errcode(db) });
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString(msg)) });
    } else {
        try arr.append(ctx.allocator, .null);
        try arr.append(ctx.allocator, .null);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn pdoSetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const attr = if (args[0] == .int) args[0].int else return NativeResult.scalar(.{ .bool = false });
    if (attr == 19) {
        try obj.set(ctx.allocator, "__default_fetch_mode", args[1]);
    } else if (attr == 3) {
        try obj.set(ctx.allocator, "__errmode", args[1]);
    }
    // general attribute storage so subsequent getAttribute() reads return the
    // last value set even for attributes that don't influence native behavior
    var key_buf: [32]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "__attr_{d}", .{attr}) catch return NativeResult.scalar(.{ .bool = true });
    const owned_key = try ctx.allocator.dupe(u8, key);
    try ctx.vm.strings.append(ctx.allocator, owned_key);
    try obj.set(ctx.allocator, owned_key, args[1]);
    return NativeResult.scalar(.{ .bool = true });
}

fn pdoGetAttribute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.null);
    const attr = args[0].int;
    if (attr == 19) {
        const mode = obj.get("__default_fetch_mode");
        if (mode == .int) return NativeResult.share(mode);
        return NativeResult.scalar(.{ .int = 4 });
    }
    if (attr == 3) {
        const m = obj.get("__errmode");
        if (m == .int) return NativeResult.share(m);
        return NativeResult.scalar(.{ .int = 2 });
    }
    if (attr == 16) return try NativeResult.copyString(ctx.allocator, getDriver(obj));
    // ATTR_SERVER_VERSION / ATTR_CLIENT_VERSION just need to return a string;
    // most callers only test is_string. zphp links sqlite at build time so a
    // generic placeholder is fine
    if (attr == 4 or attr == 5) {
        return NativeResult.literal("0");
    }
    // fall back to the generic attribute store populated by setAttribute
    var key_buf: [32]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "__attr_{d}", .{attr}) catch return NativeResult.scalar(.null);
    const stored = obj.get(key);
    if (stored != .null) return NativeResult.share(stored);
    return NativeResult.scalar(.null);
}

// PDOStatement methods

fn stmtExecute(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtExecute(ctx, obj, args);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtExecute(ctx, obj, args);
    const stmt = getStmtPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

    _ = sqlite.sqlite3_reset(stmt);

    // bind parameters if provided
    if (args.len >= 1 and args[0] == .array) {
        try bindParams(ctx, stmt, args[0].array);
    }

    const rc = try stepSqlite(ctx, stmt);
    try obj.set(ctx.allocator, "__has_row", .{ .bool = rc == sqlite.ROW });
    try obj.set(ctx.allocator, "__stepped", .{ .bool = true });

    if (rc != sqlite.ROW and rc != sqlite.DONE) {
        const db_val = obj.get("__db_ptr");
        if (db_val == .int and db_val.int != 0) {
            const db: *sqlite.Db = @ptrFromInt(@as(usize, @intCast(db_val.int)));
            const msg = std.mem.span(sqlite.sqlite3_errmsg(db));
            return throwPdo(ctx, try pdoSqlMsg(ctx, db, msg));
        }
        return NativeResult.scalar(.{ .bool = false });
    }

    // store affected rows
    const db_val = obj.get("__db_ptr");
    if (db_val == .int and db_val.int != 0) {
        const db: *sqlite.Db = @ptrFromInt(@as(usize, @intCast(db_val.int)));
        try obj.set(ctx.allocator, "__row_count", .{ .int = sqlite.sqlite3_changes(db) });
    }

    return NativeResult.scalar(.{ .bool = true });
}

fn stmtFetch(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtFetch(ctx, obj, args);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtFetch(ctx, obj, args);
    const stmt = getStmtPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

    const has_row = obj.get("__has_row");
    const stepped = obj.get("__stepped");

    // if not yet stepped (shouldn't happen after execute), step now
    if (stepped != .bool or !stepped.bool) {
        const rc = try stepSqlite(ctx, stmt);
        try obj.set(ctx.allocator, "__has_row", .{ .bool = rc == sqlite.ROW });
        try obj.set(ctx.allocator, "__stepped", .{ .bool = true });
        if (rc != sqlite.ROW) return NativeResult.scalar(.{ .bool = false });
    } else if (has_row != .bool or !has_row.bool) {
        return NativeResult.scalar(.{ .bool = false });
    }

    const mode: i64 = if (args.len >= 1 and args[0] == .int) args[0].int else getDefaultFetchMode(obj);

    if (mode == 5) {
        const row = try fetchRowAsObject(ctx, stmt);
        const next_rc = try stepSqlite(ctx, stmt);
        try obj.set(ctx.allocator, "__has_row", .{ .bool = next_rc == sqlite.ROW });
        return NativeResult.borrowed(row);
    }

    if (mode == 8) {
        // FETCH_CLASS: hydrate into the previously-configured fetch class
        const fc_v = obj.get("__fetch_class");
        const class_name: []const u8 = if (fc_v == .string) fc_v.string.bytes() else "stdClass";
        const inst = try fetchRowAsClass(ctx, stmt, class_name);
        const ctor_args_v = obj.get("__fetch_class_args");
        if (!std.mem.eql(u8, class_name, "stdClass")) {
            try invokeCtorWithArgs(ctx, inst, class_name, if (ctor_args_v == .array) ctor_args_v.array else null);
        }
        const next_rc = try stepSqlite(ctx, stmt);
        try obj.set(ctx.allocator, "__has_row", .{ .bool = next_rc == sqlite.ROW });
        return NativeResult.borrowed(inst);
    }

    if (mode == 9) {
        const target_v = obj.get("__fetch_into");
        if (target_v == .object) try populateObjectFromRow(ctx, target_v.object, stmt);
        const next_rc = try stepSqlite(ctx, stmt);
        try obj.set(ctx.allocator, "__has_row", .{ .bool = next_rc == sqlite.ROW });
        return NativeResult.share(target_v);
    }

    const row = try fetchRow(ctx, stmt, mode);

    // advance to next row
    const next_rc = try stepSqlite(ctx, stmt);
    try obj.set(ctx.allocator, "__has_row", .{ .bool = next_rc == sqlite.ROW });

    return NativeResult.borrowed(.{ .array = row });
}

fn stmtFetchAll(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtFetchAll(ctx, obj, args);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtFetchAll(ctx, obj, args);
    const stmt = getStmtPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

    const mode: i64 = if (args.len >= 1 and args[0] == .int) args[0].int else getDefaultFetchMode(obj);
    const FETCH_GROUP_FLAG: i64 = 65536;
    const FETCH_UNIQUE_FLAG: i64 = 196608;
    const base_mode = mode & 0xFFFF;
    const is_unique = (mode & FETCH_UNIQUE_FLAG) == FETCH_UNIQUE_FLAG;
    const is_group = !is_unique and (mode & FETCH_GROUP_FLAG) != 0;

    var result = try ctx.createArray();

    if (is_group or is_unique) {
        const row_mode: i64 = if (base_mode != 0) base_mode else 4;
        var first = true;
        while (true) {
            const has_row_pre0 = obj.get("__has_row");
            const stepped_pre0 = obj.get("__stepped");
            const start_with_row0 = first and stepped_pre0 == .bool and stepped_pre0.bool and has_row_pre0 == .bool and has_row_pre0.bool;
            if (!start_with_row0) {
                const rc = try stepSqlite(ctx, stmt);
                if (rc != sqlite.ROW) break;
            }
            first = false;
            // first column is the group/unique key
            const key_v = try columnToValue(ctx, stmt, 0);
            defer if (key_v == .string) key_v.string.release();
            const ak: PhpArray.Key = switch (key_v) {
                .string => |s| .{ .string = s },
                .int => |n| .{ .int = n },
                else => .{ .int = Value.toInt(key_v) },
            };

            // for FETCH_COLUMN the per-row value is the next column scalar;
            // for FETCH_NUM/ASSOC/BOTH the per-row value is a row array
            var row_value: Value = .null;
            defer if (row_value == .string) row_value.string.release();
            if (row_mode == 7) {
                const col_count_c = sqlite.sqlite3_column_count(stmt);
                row_value = if (col_count_c > 1) try columnToValue(ctx, stmt, 1) else .null;
            } else {
                var inner = try ctx.createArray();
                const col_count = sqlite.sqlite3_column_count(stmt);
                var i: c_int = 1;
                while (i < col_count) : (i += 1) {
                    const v = try columnToValue(ctx, stmt, i);
                    defer if (v == .string) v.string.release();
                    if (row_mode == 3 or row_mode == 4) try inner.append(ctx.allocator, v);
                    if (row_mode == 2 or row_mode == 4) {
                        if (sqlite.sqlite3_column_name(stmt, i)) |np| {
                            const name = try Value.String.create(ctx.allocator, std.mem.span(np));
                            defer name.release();
                            try inner.set(ctx.allocator, .{ .string = name }, v);
                        }
                    }
                }
                row_value = .{ .array = inner };
            }

            if (is_unique) {
                try result.set(ctx.allocator, ak, row_value);
            } else {
                // group: collect rows under the key
                const existing = result.get(ak);
                if (existing == .array) {
                    try existing.array.append(ctx.allocator, row_value);
                } else {
                    const group = try ctx.allocator.create(PhpArray);
                    group.* = .{};
                    try ctx.vm.arrays.append(ctx.allocator, group);
                    try group.append(ctx.allocator, row_value);
                    try result.set(ctx.allocator, ak, .{ .array = group });
                }
            }
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return NativeResult.borrowed(.{ .array = result });
    }

    if (mode == 5) {
        try fetchAllAsObjects(ctx, stmt, result, obj);
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return NativeResult.borrowed(.{ .array = result });
    }

    const has_row_pre = obj.get("__has_row");
    const stepped_pre = obj.get("__stepped");
    const start_with_row = stepped_pre == .bool and stepped_pre.bool and has_row_pre == .bool and has_row_pre.bool;

    // FETCH_CLASS (8): hydrate rows into instances of the given class
    if (mode == 8) {
        var class_name: []const u8 = "stdClass";
        if (args.len >= 2 and args[1] == .string) class_name = args[1].string.bytes();
        const ctor_args_arr: ?*PhpArray = if (args.len >= 3 and args[2] == .array) args[2].array else null;
        // PHP calls __construct after populating properties unless FETCH_PROPS_LATE flag
        const is_stdclass = std.mem.eql(u8, class_name, "stdClass");
        if (start_with_row) {
            const inst = try fetchRowAsClass(ctx, stmt, class_name);
            if (!is_stdclass) {
                if (ctor_args_arr) |ca| try invokeCtorWithArgs(ctx, inst, class_name, ca) else try invokeCtorWithArgs(ctx, inst, class_name, null);
            }
            try result.append(ctx.allocator, inst);
        }
        var rc = try stepSqlite(ctx, stmt);
        while (rc == sqlite.ROW) {
            const inst = try fetchRowAsClass(ctx, stmt, class_name);
            if (!is_stdclass) {
                if (ctor_args_arr) |ca| try invokeCtorWithArgs(ctx, inst, class_name, ca) else try invokeCtorWithArgs(ctx, inst, class_name, null);
            }
            try result.append(ctx.allocator, inst);
            rc = try stepSqlite(ctx, stmt);
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return NativeResult.borrowed(.{ .array = result });
    }

    // FETCH_INTO (9): populate the previously-set fetch-into target
    if (mode == 9) {
        const target_v = obj.get("__fetch_into");
        if (target_v != .object) {
            try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
            return NativeResult.borrowed(.{ .array = result });
        }
        const target = target_v.object;
        if (start_with_row) {
            try populateObjectFromRow(ctx, target, stmt);
            try result.append(ctx.allocator, .{ .object = target });
        }
        var rc = try stepSqlite(ctx, stmt);
        while (rc == sqlite.ROW) {
            try populateObjectFromRow(ctx, target, stmt);
            try result.append(ctx.allocator, .{ .object = target });
            rc = try stepSqlite(ctx, stmt);
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return NativeResult.borrowed(.{ .array = result });
    }

    // FETCH_FUNC (10): pass each row's columns as args to a callable, collect
    // the return value as the row in the result array
    if (mode == 10) {
        if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
        const callable = args[1];
        const col_count = sqlite.sqlite3_column_count(stmt);
        if (start_with_row) {
            var call_args = try ctx.allocator.alloc(Value, @intCast(col_count));
            defer ctx.allocator.free(call_args);
            var i: c_int = 0;
            while (i < col_count) : (i += 1) call_args[@intCast(i)] = try columnToValue(ctx, stmt, i);
            defer for (call_args) |a| if (a == .string) a.string.release();
            const r = try ctx.invokeCallable(callable, call_args);
            try result.append(ctx.allocator, r);
        }
        var rc = try stepSqlite(ctx, stmt);
        while (rc == sqlite.ROW) {
            var call_args = try ctx.allocator.alloc(Value, @intCast(col_count));
            defer ctx.allocator.free(call_args);
            var i: c_int = 0;
            while (i < col_count) : (i += 1) call_args[@intCast(i)] = try columnToValue(ctx, stmt, i);
            defer for (call_args) |a| if (a == .string) a.string.release();
            const r = try ctx.invokeCallable(callable, call_args);
            try result.append(ctx.allocator, r);
            rc = try stepSqlite(ctx, stmt);
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return NativeResult.borrowed(.{ .array = result });
    }

    // FETCH_KEY_PAIR (12): col 0 = key, col 1 = value
    if (mode == 12) {
        if (start_with_row) {
            const key_v = try columnToValue(ctx, stmt, 0);
            defer if (key_v == .string) key_v.string.release();
            const val_v = try columnToValue(ctx, stmt, 1);
            defer if (val_v == .string) val_v.string.release();
            const ak: PhpArray.Key = switch (key_v) {
                .string => |s| .{ .string = s },
                .int => |n| .{ .int = n },
                else => .{ .int = Value.toInt(key_v) },
            };
            try result.set(ctx.allocator, ak, val_v);
        }
        var rc = try stepSqlite(ctx, stmt);
        while (rc == sqlite.ROW) {
            const key_v = try columnToValue(ctx, stmt, 0);
            defer if (key_v == .string) key_v.string.release();
            const val_v = try columnToValue(ctx, stmt, 1);
            defer if (val_v == .string) val_v.string.release();
            const ak: PhpArray.Key = switch (key_v) {
                .string => |s| .{ .string = s },
                .int => |n| .{ .int = n },
                else => .{ .int = Value.toInt(key_v) },
            };
            try result.set(ctx.allocator, ak, val_v);
            rc = try stepSqlite(ctx, stmt);
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return NativeResult.borrowed(.{ .array = result });
    }

    // FETCH_COLUMN (7): single column from each row, default col 0
    if (mode == 7) {
        const col_idx: c_int = if (args.len >= 2 and args[1] == .int) @intCast(args[1].int) else 0;
        if (start_with_row) {
            const val_v = try columnToValue(ctx, stmt, col_idx);
            defer if (val_v == .string) val_v.string.release();
            try result.append(ctx.allocator, val_v);
        }
        var rc = try stepSqlite(ctx, stmt);
        while (rc == sqlite.ROW) {
            const val_v = try columnToValue(ctx, stmt, col_idx);
            defer if (val_v == .string) val_v.string.release();
            try result.append(ctx.allocator, val_v);
            rc = try stepSqlite(ctx, stmt);
        }
        try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
        return NativeResult.borrowed(.{ .array = result });
    }

    const has_row = obj.get("__has_row");
    const stepped = obj.get("__stepped");

    if (stepped != .bool or !stepped.bool) {
        var rc = try stepSqlite(ctx, stmt);
        while (rc == sqlite.ROW) {
            const row = try fetchRow(ctx, stmt, mode);
            try result.append(ctx.allocator, .{ .array = row });
            rc = try stepSqlite(ctx, stmt);
        }
    } else {
        if (has_row == .bool and has_row.bool) {
            const row = try fetchRow(ctx, stmt, mode);
            try result.append(ctx.allocator, .{ .array = row });
            var rc = try stepSqlite(ctx, stmt);
            while (rc == sqlite.ROW) {
                const next_row = try fetchRow(ctx, stmt, mode);
                try result.append(ctx.allocator, .{ .array = next_row });
                rc = try stepSqlite(ctx, stmt);
            }
        }
    }

    try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    return NativeResult.borrowed(.{ .array = result });
}

fn stmtFetchColumn(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtFetchColumn(ctx, obj, args);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtFetchColumn(ctx, obj, args);
    const stmt = getStmtPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });

    const col: c_int = if (args.len >= 1 and args[0] == .int) @intCast(args[0].int) else 0;

    const has_row = obj.get("__has_row");
    const stepped = obj.get("__stepped");

    if (stepped != .bool or !stepped.bool) {
        const rc = try stepSqlite(ctx, stmt);
        if (rc != sqlite.ROW) return NativeResult.scalar(.{ .bool = false });
    } else if (has_row != .bool or !has_row.bool) {
        return NativeResult.scalar(.{ .bool = false });
    }

    const val = try columnToValue(ctx, stmt, col);

    const next_rc = try stepSqlite(ctx, stmt);
    try obj.set(ctx.allocator, "__has_row", .{ .bool = next_rc == sqlite.ROW });
    try obj.set(ctx.allocator, "__stepped", .{ .bool = true });

    if (val == .string) return NativeResult.takeString(val.string);
    return NativeResult.scalar(val);
}

fn stmtRowCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = getDriver(obj);
    // for SELECT statements, sqlite doesn't track row count
    const stmt = getStmtPtr(obj);
    if (stmt) |s| {
        if (sqlite.sqlite3_stmt_readonly(s) != 0) return NativeResult.scalar(.{ .int = 0 });
    }
    const rc = obj.get("__row_count");
    if (rc == .int) return NativeResult.share(rc);
    return NativeResult.scalar(.{ .int = 0 });
}

fn stmtColumnCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtColumnCount(obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtColumnCount(obj);
    // PHP returns 0 before execute
    const stepped = obj.get("__stepped");
    if (stepped != .bool or !stepped.bool) return NativeResult.scalar(.{ .int = 0 });
    const stmt = getStmtPtr(obj) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = sqlite.sqlite3_column_count(stmt) });
}

fn stmtCloseCursor(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql")) return pdo_mysql.stmtCloseCursor(ctx, obj);
    if (std.mem.eql(u8, drv, "pgsql")) return pdo_pgsql.stmtCloseCursor(ctx, obj);
    const stmt = getStmtPtr(obj) orelse return NativeResult.scalar(.{ .bool = true });
    _ = sqlite.sqlite3_reset(stmt);
    try obj.set(ctx.allocator, "__has_row", .{ .bool = false });
    try obj.set(ctx.allocator, "__stepped", .{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn stmtSetFetchMode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const mode: Value = if (args.len >= 1) args[0] else .{ .int = 4 };
    try obj.set(ctx.allocator, "__fetch_mode", mode);
    if (mode == .int and mode.int == 9 and args.len >= 2 and args[1] == .object) {
        try obj.set(ctx.allocator, "__fetch_into", args[1]);
    }
    if (mode == .int and mode.int == 8 and args.len >= 2 and args[1] == .string) {
        try obj.set(ctx.allocator, "__fetch_class", args[1]);
        if (args.len >= 3 and args[2] == .array) try obj.set(ctx.allocator, "__fetch_class_args", args[2]);
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn invokeCtorWithArgs(ctx: *NativeContext, inst_val: Value, class_name: []const u8, ctor_args: ?*PhpArray) !void {
    if (inst_val != .object) return;
    if (!ctx.vm.hasMethod(class_name, "__construct")) return;
    const obj = inst_val.object;
    var args_buf: [16]Value = undefined;
    var ai: usize = 0;
    if (ctor_args) |arr| {
        for (arr.entries.items) |e| {
            if (ai >= args_buf.len) break;
            args_buf[ai] = e.value;
            ai += 1;
        }
    }
    _ = try ctx.vm.callMethod(obj, "__construct", args_buf[0..ai]);
}

fn populateObjectFromRow(ctx: *NativeContext, obj: *PhpObject, stmt: *sqlite.Stmt) !void {
    const col_count = sqlite.sqlite3_column_count(stmt);
    var i: c_int = 0;
    while (i < col_count) : (i += 1) {
        if (sqlite.sqlite3_column_name(stmt, i)) |name_ptr| {
            const name = std.mem.span(name_ptr);
            const owned = try ctx.createString(name);
            const val = try columnToValue(ctx, stmt, i);
            defer if (val == .string) val.string.release();
            try obj.set(ctx.allocator, owned, val);
        }
    }
}

fn pdoQuote(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.{ .bool = false });
    var s_buf: [4096]u8 = undefined;
    const v = args[0];
    var input: []const u8 = "";
    var fallback: [32]u8 = undefined;
    switch (v) {
        .string => |s| input = s.bytes(),
        .int => |n| input = std.fmt.bufPrint(&fallback, "{d}", .{n}) catch return NativeResult.scalar(.{ .bool = false }),
        .float => |f| input = std.fmt.bufPrint(&fallback, "{d}", .{f}) catch return NativeResult.scalar(.{ .bool = false }),
        .bool => |b| input = if (b) "1" else "",
        .null => input = "",
        else => return NativeResult.scalar(.{ .bool = false }),
    }
    // single-quote and double internal quotes per SQL standard
    var w: usize = 0;
    if (w + 1 >= s_buf.len) return NativeResult.scalar(.{ .bool = false });
    s_buf[w] = '\'';
    w += 1;
    for (input) |c| {
        if (c == '\'') {
            if (w + 2 >= s_buf.len) return NativeResult.scalar(.{ .bool = false });
            s_buf[w] = '\'';
            w += 1;
            s_buf[w] = '\'';
            w += 1;
        } else {
            if (w + 1 >= s_buf.len) return NativeResult.scalar(.{ .bool = false });
            s_buf[w] = c;
            w += 1;
        }
    }
    if (w + 1 >= s_buf.len) return NativeResult.scalar(.{ .bool = false });
    s_buf[w] = '\'';
    w += 1;
    const result = try Value.String.create(ctx.allocator, s_buf[0..w]);
    return NativeResult.takeString(result);
}

fn pdoInTransaction(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const t = obj.get("__in_transaction");
    return NativeResult.scalar(.{ .bool = t == .bool and t.bool });
}

fn pdoGetAvailableDrivers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("sqlite") });
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("mysql") });
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("pgsql") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn pdoErrorCode(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const code = obj.get("__error_code");
    if (code == .string) return NativeResult.share(code);
    return NativeResult.literal("00000");
}

fn stmtErrorCode(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const code = obj.get("__error_code");
    if (code == .string) return NativeResult.share(code);
    return NativeResult.literal("00000");
}

fn stmtErrorInfo(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    const code = obj.get("__error_code");
    try arr.append(ctx.allocator, if (code == .string) code else .{ .string = Value.String.borrowed("00000") });
    const driver_code = obj.get("__driver_error_code");
    try arr.append(ctx.allocator, if (driver_code == .int) driver_code else .null);
    const msg = obj.get("__error_message");
    try arr.append(ctx.allocator, if (msg == .string) msg else .null);
    return NativeResult.borrowed(.{ .array = arr });
}

fn stmtDebugDumpParams(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn stmtGetColumnMeta(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1 or args[0] != .int) return NativeResult.scalar(.{ .bool = false });
    const stmt = getStmtPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const col: c_int = @intCast(args[0].int);
    const arr = try ctx.createArray();
    if (sqlite.sqlite3_column_name(stmt, col)) |np| {
        const n = std.mem.span(np);
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed("name") }, .{ .string = Value.String.borrowed(try ctx.createString(n)) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn stmtNextRowset(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = false });
}

fn stmtBindValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 2) return NativeResult.scalar(.{ .bool = false });
    const drv = getDriver(obj);
    if (std.mem.eql(u8, drv, "mysql") or std.mem.eql(u8, drv, "pgsql")) return NativeResult.scalar(.{ .bool = true });
    const stmt = getStmtPtr(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const param = args[0];
    const val = args[1];
    const idx: c_int = if (param == .int) @intCast(param.int) else blk: {
        if (param != .string) break :blk @as(c_int, 0);
        const name = param.string.bytes();
        const has_prefix = name.len > 0 and (name[0] == ':' or name[0] == '@' or name[0] == '$');
        const buf = ctx.allocator.alloc(u8, name.len + (if (has_prefix) @as(usize, 1) else @as(usize, 2))) catch break :blk @as(c_int, 0);
        defer ctx.allocator.free(buf);
        if (has_prefix) {
            @memcpy(buf[0..name.len], name);
            buf[name.len] = 0;
        } else {
            buf[0] = ':';
            @memcpy(buf[1 .. 1 + name.len], name);
            buf[1 + name.len] = 0;
        }
        break :blk sqlite.sqlite3_bind_parameter_index(stmt, @ptrCast(buf.ptr));
    };
    if (idx == 0) return NativeResult.scalar(.{ .bool = false });
    const rc = switch (val) {
        .int => sqlite.sqlite3_bind_int64(stmt, idx, val.int),
        .float => sqlite.sqlite3_bind_double(stmt, idx, val.float),
        .string => sqlite.sqlite3_bind_text(stmt, idx, @ptrCast(val.string.bytes().ptr), @intCast(val.string.bytes().len), null),
        .null => sqlite.sqlite3_bind_null(stmt, idx),
        .bool => sqlite.sqlite3_bind_int64(stmt, idx, if (val.bool) 1 else 0),
        else => sqlite.sqlite3_bind_null(stmt, idx),
    };
    return NativeResult.scalar(.{ .bool = rc == sqlite.OK });
}

fn getDefaultFetchMode(obj: *PhpObject) i64 {
    const mode = obj.get("__fetch_mode");
    if (mode == .int) return mode.int;
    // fall back to the parent PDO's default fetch mode
    const pdo = obj.get("__pdo");
    if (pdo == .object) {
        const dm = pdo.object.get("__default_fetch_mode");
        if (dm == .int) return dm.int;
    }
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
        defer if (val == .string) val.string.release();
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
            defer if (val == .string) val.string.release();
            try obj.set(ctx.allocator, owned, val);
        }
    }
    return .{ .object = obj };
}

fn fetchAllAsObjects(ctx: *NativeContext, stmt: *sqlite.Stmt, result: *PhpArray, obj_parent: *PhpObject) !void {
    const has_row = obj_parent.get("__has_row");
    const stepped = obj_parent.get("__stepped");

    if (stepped != .bool or !stepped.bool) {
        var rc = try stepSqlite(ctx, stmt);
        while (rc == sqlite.ROW) {
            const row = try fetchRowAsObject(ctx, stmt);
            try result.append(ctx.allocator, row);
            rc = try stepSqlite(ctx, stmt);
        }
    } else {
        if (has_row == .bool and has_row.bool) {
            const row = try fetchRowAsObject(ctx, stmt);
            try result.append(ctx.allocator, row);
            var rc = try stepSqlite(ctx, stmt);
            while (rc == sqlite.ROW) {
                const next_row = try fetchRowAsObject(ctx, stmt);
                try result.append(ctx.allocator, next_row);
                rc = try stepSqlite(ctx, stmt);
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
        defer if (val == .string) val.string.release();
        // FETCH_BOTH places named key before numeric per column to match php
        if (mode == 4) {
            if (sqlite.sqlite3_column_name(stmt, i)) |name_ptr| {
                const key = try Value.String.create(ctx.allocator, std.mem.span(name_ptr));
                defer key.release();
                try row.set(ctx.allocator, .{ .string = key }, val);
            }
            try row.append(ctx.allocator, val);
        } else if (mode == 3) {
            try row.append(ctx.allocator, val);
        } else if (mode == 2) {
            if (sqlite.sqlite3_column_name(stmt, i)) |name_ptr| {
                const key = try Value.String.create(ctx.allocator, std.mem.span(name_ptr));
                defer key.release();
                try row.set(ctx.allocator, .{ .string = key }, val);
            }
        } else if (mode == 11) {
            // FETCH_NAMED: same as FETCH_ASSOC, but duplicate column names
            // collapse into an array of values rather than overwriting
            if (sqlite.sqlite3_column_name(stmt, i)) |name_ptr| {
                const key_s = try Value.String.create(ctx.allocator, std.mem.span(name_ptr));
                defer key_s.release();
                const key = PhpArray.Key{ .string = key_s };
                const existing = row.get(key);
                if (existing == .null) {
                    try row.set(ctx.allocator, key, val);
                } else if (existing == .array) {
                    try existing.array.append(ctx.allocator, val);
                } else {
                    const sub = try ctx.createArray();
                    try sub.append(ctx.allocator, existing);
                    try sub.append(ctx.allocator, val);
                    try row.set(ctx.allocator, key, .{ .array = sub });
                }
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
            const text = sqlite.sqlite3_column_text(stmt, col) orelse break :blk Value{ .string = try Value.String.create(ctx.allocator, "") };
            const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, col));
            break :blk Value{ .string = try Value.String.create(ctx.allocator, text[0..len]) };
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
                if (name.len > 0 and name.bytes()[0] == ':') {
                    const z = try dupeZ(ctx, name.bytes());
                    break :blk sqlite.sqlite3_bind_parameter_index(stmt, z);
                }
                var buf: [256]u8 = undefined;
                buf[0] = ':';
                if (name.len < 255) {
                    @memcpy(buf[1 .. name.len + 1], name.bytes());
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
            .string => |s| _ = sqlite.sqlite3_bind_text(stmt, idx, s.bytes().ptr, @intCast(s.bytes().len), null),
            else => _ = sqlite.sqlite3_bind_null(stmt, idx),
        }
    }
}
