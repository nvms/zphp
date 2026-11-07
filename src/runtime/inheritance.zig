// php's method inheritance checks (zend_inheritance.c): when a class is
// declared, every method it overrides and every interface method it
// implements is checked as do_inheritance_check_on_method checks it: final,
// static, abstract, visibility, and the signature
// (zend_do_perform_implementation_check), with its errors worded as php's

const std = @import("std");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const ClassDef = vm_mod.ClassDef;
const RuntimeError = vm_mod.RuntimeError;
const Value = @import("value.zig").Value;
const bytecode = @import("../pipeline/bytecode.zig");
const php_types = @import("php_types.zig");
const native_params = @import("../stdlib/native_params.zig");
const interface_signatures = @import("../stdlib/interface_signatures_generated.zig");

const Param = struct {
    name: []const u8,
    type_text: []const u8,
    by_ref: bool,
    variadic: bool,
    // how php prints the default in a declaration; null for a required one
    default_text: ?[]const u8,
};

const Method = struct {
    class: []const u8,
    name: []const u8,
    // the class or trait whose code it is: a trait's method keeps its
    // attributes on the trait
    origin: []const u8,
    params: []const Param,
    required: usize,
    variadic: bool,
    returns_ref: bool,
    return_text: []const u8,
    tentative: bool,
    visibility: ClassDef.Visibility,
    is_static: bool,
    is_abstract: bool,
    is_final: bool,
    // php's internal functions have no file or line
    file: []const u8,
    line: u32,
};

// the class being declared: not in the class table yet
const Pending = struct {
    vm: *VM,
    name: []const u8,
    def: *const ClassDef,
    // an error an autoloader raised while a check looked a class up; the
    // variance callbacks can only answer yes or no, so it is raised after
    failure: ?RuntimeError = null,
};

fn pendingIs(p: *const Pending, name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(p.name, name);
}

fn classExists(context: *anyopaque, name: []const u8) bool {
    const p: *Pending = @ptrCast(@alignCast(context));
    if (pendingIs(p, name)) return true;
    if (p.vm.classes.contains(name) or p.vm.interfaces.contains(name)) return true;
    if (p.failure != null) return false;
    p.vm.tryAutoload(name) catch |err| {
        p.failure = err;
        return false;
    };
    return p.vm.classes.contains(name) or p.vm.interfaces.contains(name);
}

fn classSubtype(context: *anyopaque, child: []const u8, ancestor: []const u8) bool {
    const p: *const Pending = @ptrCast(@alignCast(context));
    if (std.ascii.eqlIgnoreCase(child, ancestor)) return true;
    const def: *const ClassDef = if (pendingIs(p, child)) p.def else if (p.vm.classes.getPtr(child)) |d| d else {
        const iface = p.vm.interfaces.getPtr(child) orelse return false;
        if (iface.parent) |parent| if (classSubtype(context, parent, ancestor)) return true;
        for (iface.parents.items) |parent| if (classSubtype(context, parent, ancestor)) return true;
        return false;
    };
    if (def.parent) |parent| if (classSubtype(context, parent, ancestor)) return true;
    for (def.interfaces.items) |iface| if (classSubtype(context, iface, ancestor)) return true;
    return false;
}

fn classFinal(context: *anyopaque, name: []const u8) bool {
    const p: *const Pending = @ptrCast(@alignCast(context));
    if (pendingIs(p, name)) return p.def.is_final;
    const def = p.vm.classes.get(name) orelse return false;
    return def.is_final;
}

fn defOf(p: *const Pending, name: []const u8) ?*const ClassDef {
    if (pendingIs(p, name)) return p.def;
    return p.vm.classes.getPtr(name);
}

fn parentOf(p: *const Pending, class: []const u8) ?[]const u8 {
    const def = defOf(p, class) orelse return null;
    return def.parent;
}

// how zend_get_function_declaration prints a user default
fn userDefaultText(arena: std.mem.Allocator, value: Value) ![]const u8 {
    return switch (value) {
        .null, .undef => "null",
        .bool => |b| if (b) "true" else "false",
        .int => |i| try std.fmt.allocPrint(arena, "{d}", .{i}),
        .float => blk: {
            var list: std.ArrayListUnmanaged(u8) = .empty;
            try value.format(&list, arena);
            break :blk list.items;
        },
        .string => |s| blk: {
            const bytes = s.bytes();
            if (bytecode.deferredExprPtr(bytes) != null or bytecode.newDefaultPtr(bytes) != null) break :blk "<expression>";
            // a constant the compiler left to resolve: "\0CC\0<class>\0<name>"
            if (bytes.len > 4 and bytes[0] == 0 and bytes[1] == 'C' and bytes[2] == 'C' and bytes[3] == 0) {
                const rest = bytes[4..];
                const sep = std.mem.indexOfScalar(u8, rest, 0) orelse break :blk "<expression>";
                if (sep == 0) break :blk rest[1..];
                break :blk try std.fmt.allocPrint(arena, "{s}::{s}", .{ rest[0..sep], rest[sep + 1 ..] });
            }
            if (bytes.len > 10) break :blk try std.fmt.allocPrint(arena, "'{s}...'", .{bytes[0..10]});
            break :blk try std.fmt.allocPrint(arena, "'{s}'", .{bytes});
        },
        .array => if (value.isEmptyArrayDefault() or value.array.entries.items.len == 0) "[]" else "[...]",
        else => "<expression>",
    };
}

fn internalDefaultText(arena: std.mem.Allocator, param: native_params.Param) !?[]const u8 {
    if (param.default_constant.len > 0) return param.default_constant;
    return switch (param.default) {
        .required => null,
        .unknown => "<default>",
        .null => "null",
        .bool => |b| if (b) "true" else "false",
        .int => |i| try std.fmt.allocPrint(arena, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(arena, "{d}", .{f}),
        .string => |s| try std.fmt.allocPrint(arena, "\"{s}\"", .{s}),
        .empty_array => "[]",
        else => "<default>",
    };
}

fn declaredMethodInfo(p: *const Pending, class: []const u8, name: []const u8) ?ClassDef.MethodInfo {
    const def = defOf(p, class) orelse return null;
    return def.methods.get(name);
}

// the method `name` as `class` declares it, user or internal
fn methodOf(p: *const Pending, arena: std.mem.Allocator, class: []const u8, name: []const u8, is_interface: bool) !?Method {
    const vm = p.vm;
    const key = try std.fmt.allocPrint(arena, "{s}::{s}", .{ class, name });
    const info = declaredMethodInfo(p, class, name);
    if (vm.functions.get(key)) |func| {
        const types = vm_mod.getTypeInfo(key) orelse vm_mod.getTypeInfo(func.name);
        var params = try arena.alloc(Param, func.params.len);
        for (func.params, 0..) |raw, i| {
            const param_name = if (raw.len > 0 and raw[0] == '$') raw[1..] else raw;
            const variadic = func.is_variadic and i == func.params.len - 1;
            params[i] = .{
                .name = param_name,
                .type_text = if (types) |t| (if (i < t.param_types.len) t.param_types[i] else "") else "",
                .by_ref = i < func.ref_params.len and func.ref_params[i],
                .variadic = variadic,
                .default_text = if (i >= func.required_params and !variadic and i < func.defaults.len) try userDefaultText(arena, func.defaults[i]) else null,
            };
        }
        const origin = if (std.mem.indexOf(u8, func.name, "::")) |sep| func.name[0..sep] else class;
        return .{
            .class = class,
            .name = if (info) |m| m.name else name,
            .origin = origin,
            .params = params,
            .required = func.required_params,
            .variadic = func.is_variadic,
            .returns_ref = func.returns_ref,
            .return_text = if (types) |t| t.return_type else "",
            .tentative = false,
            .visibility = if (info) |m| m.visibility else .public,
            .is_static = func.is_static or (if (info) |m| m.is_static else false),
            .is_abstract = is_interface or (if (info) |m| m.is_abstract else false),
            .is_final = if (info) |m| m.is_final else false,
            .file = func.file_path,
            .line = func.start_line,
        };
    }
    const signature = interface_signatures.map.get(key) orelse native_params.get(key) orelse return null;
    var params = try arena.alloc(Param, signature.params.len);
    var required: usize = 0;
    var variadic = false;
    for (signature.params, 0..) |param, i| {
        if (param.default == .required and !param.variadic) required = i + 1;
        if (param.variadic) variadic = true;
        params[i] = .{
            .name = param.name,
            .type_text = param.type,
            .by_ref = param.by_ref,
            .variadic = param.variadic,
            .default_text = if (param.variadic) null else try internalDefaultText(arena, param),
        };
    }
    const tentative = signature.tentative_returns.len > 0;
    return .{
        .class = class,
        .name = if (info) |m| m.name else name,
        .origin = class,
        .params = params,
        .required = required,
        .variadic = variadic,
        .returns_ref = false,
        .return_text = if (tentative) signature.tentative_returns else signature.returns,
        .tentative = tentative,
        .visibility = if (info) |m| m.visibility else .public,
        .is_static = signature.is_static or (if (info) |m| m.is_static else false),
        .is_abstract = is_interface,
        .is_final = if (info) |m| m.is_final else false,
        .file = "",
        .line = 0,
    };
}

fn parseType(p: *const Pending, arena: std.mem.Allocator, text: []const u8, scope: []const u8) !php_types.Type {
    return php_types.parse(arena, text, scope, parentOf(p, scope));
}

// zend_get_function_declaration
fn declaration(p: *const Pending, arena: std.mem.Allocator, m: Method) ![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    if (m.returns_ref) try out.appendSlice(arena, "& ");
    try out.print(arena, "{s}::{s}(", .{ m.class, m.name });
    for (m.params, 0..) |param, i| {
        if (i > 0) try out.appendSlice(arena, ", ");
        if (param.type_text.len > 0) {
            const t = try parseType(p, arena, param.type_text, m.class);
            try out.appendSlice(arena, try php_types.format(arena, t));
            try out.append(arena, ' ');
        }
        if (param.by_ref) try out.append(arena, '&');
        if (param.variadic) try out.appendSlice(arena, "...");
        try out.print(arena, "${s}", .{param.name});
        if (!param.variadic and i >= m.required) if (param.default_text) |text| try out.print(arena, " = {s}", .{text});
    }
    try out.append(arena, ')');
    if (m.return_text.len > 0) {
        const t = try parseType(p, arena, m.return_text, m.class);
        try out.print(arena, ": {s}", .{try php_types.format(arena, t)});
    }
    return out.items;
}

const Outcome = enum { success, failure, warning, unresolved };

fn classes(p: *Pending) php_types.Classes {
    return .{ .context = p, .exists = classExists, .subtype = classSubtype, .is_final = classFinal };
}

// zend_do_perform_implementation_check
fn implementationCheck(p: *Pending, arena: std.mem.Allocator, fe: Method, proto: Method) !Outcome {
    if (proto.required < fe.required) return .failure;
    if (proto.returns_ref and !fe.returns_ref) return .failure;
    if (proto.variadic and !fe.variadic) return .failure;
    const count = @max(proto.params.len, fe.params.len);
    var status: Outcome = .success;
    for (0..count) |i| {
        const proto_param: ?Param = if (i < proto.params.len) proto.params[i] else if (proto.variadic) proto.params[proto.params.len - 1] else null;
        const fe_param: ?Param = if (i < fe.params.len) fe.params[i] else if (fe.variadic) fe.params[fe.params.len - 1] else null;
        const pp = proto_param orelse continue;
        const fp = fe_param orelse return .failure;
        // zend_do_perform_arg_type_hint_check, contravariant
        const fe_type = try parseType(p, arena, fp.type_text, fe.class);
        if (fe_type.isSet() and !(fe_type.mask == php_types.ANY and fe_type.names.len == 0 and fe_type.intersections.len == 0)) {
            const proto_type = try parseType(p, arena, pp.type_text, proto.class);
            if (!proto_type.isSet()) return .failure;
            switch (php_types.covariant(classes(p), proto.class, proto_type, fe_type)) {
                .success => {},
                .failure => return .failure,
                .unresolved => status = .unresolved,
            }
        }
        if (fp.by_ref != pp.by_ref) return .failure;
    }
    if (proto.return_text.len > 0) {
        if (fe.return_text.len == 0) {
            if (!proto.tentative) return .failure;
            return if (status == .success) .warning else status;
        }
        const fe_type = try parseType(p, arena, fe.return_text, fe.class);
        const proto_type = try parseType(p, arena, proto.return_text, proto.class);
        switch (php_types.covariant(classes(p), fe.class, fe_type, proto_type)) {
            .success => {},
            .failure => return if (proto.tentative) .warning else .failure,
            .unresolved => return .unresolved,
        }
    }
    return status;
}

fn hasReturnTypeWillChange(p: *const Pending, m: Method) bool {
    const def = defOf(p, m.class) orelse return false;
    const attrs = def.method_attributes.get(m.name) orelse blk: {
        const origin = defOf(p, m.origin) orelse return false;
        break :blk origin.method_attributes.get(m.name) orelse return false;
    };
    for (attrs) |attr| {
        const n = if (attr.name.len > 0 and attr.name[0] == '\\') attr.name[1..] else attr.name;
        if (std.ascii.eqlIgnoreCase(n, "ReturnTypeWillChange")) return true;
    }
    return false;
}

fn fatal(vm: *VM, m: Method, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(vm.allocator, fmt, args);
    defer vm.allocator.free(msg);
    return vm.raiseCompileFatal(msg, .{ .file = if (m.file.len > 0) m.file else vm.currentSourcePosition().file, .line = if (m.line > 0) m.line else vm.currentSourcePosition().line });
}

fn visibilityName(v: ClassDef.Visibility) []const u8 {
    return switch (v) {
        .public => "public",
        .protected => "protected",
        .private => "private",
    };
}

// do_inheritance_check_on_method with CHECK_PROTO and CHECK_VISIBILITY
fn checkMethod(p: *Pending, arena: std.mem.Allocator, child: Method, parent: Method, is_ctor: bool) RuntimeError!void {
    const vm = p.vm;
    if (parent.visibility == .private and !parent.is_abstract and !is_ctor) return;
    if (parent.is_final) return fatal(vm, child, "Cannot override final method {s}::{s}()", .{ parent.class, child.name });
    if (child.is_static != parent.is_static) {
        if (child.is_static) return fatal(vm, child, "Cannot make non static method {s}::{s}() static in class {s}", .{ parent.class, child.name, child.class });
        return fatal(vm, child, "Cannot make static method {s}::{s}() non static in class {s}", .{ parent.class, child.name, child.class });
    }
    if (child.is_abstract and !parent.is_abstract) return fatal(vm, child, "Cannot make non abstract method {s}::{s}() abstract in class {s}", .{ parent.class, child.name, child.class });
    // a constructor is only checked against an abstract or interface one
    if (is_ctor and !parent.is_abstract) return;
    if (@backingInt(child.visibility) > @backingInt(parent.visibility)) {
        return fatal(vm, child, "Access level to {s}::{s}() must be {s} (as in class {s}){s}", .{ child.class, child.name, visibilityName(parent.visibility), parent.class, if (parent.visibility == .public) "" else " or weaker" });
    }
    const outcome = implementationCheck(p, arena, child, parent) catch return error.OutOfMemory;
    if (p.failure) |err| return err;
    switch (outcome) {
        .success => {},
        .failure => return fatal(vm, child, "Declaration of {s} must be compatible with {s}", .{ try declaration(p, arena, child), try declaration(p, arena, parent) }),
        .warning => if (!hasReturnTypeWillChange(p, child)) {
            const msg = try std.fmt.allocPrint(arena, "Return type of {s} should either be compatible with {s}, or the #[\\ReturnTypeWillChange] attribute should be used to temporarily suppress the notice", .{ try declaration(p, arena, child), try declaration(p, arena, parent) });
            try vm.raiseErrorAt(VM.E_DEPRECATED, msg, .{ .file = if (child.file.len > 0) child.file else vm.currentSourcePosition().file, .line = child.line });
        },
        .unresolved => {
            // the classes a variance check needs were looked up (loading them
            // through autoloaders); one that still doesn't exist ends it here
            const missing = try missingClass(p, arena, child, parent);
            return fatal(vm, child, "Could not check compatibility between {s} and {s}, because class {s} is not available", .{ try declaration(p, arena, child), try declaration(p, arena, parent), missing });
        },
    }
}

fn missingClass(p: *Pending, arena: std.mem.Allocator, child: Method, parent: Method) ![]const u8 {
    for ([_]Method{ child, parent }) |m| {
        var texts: std.ArrayListUnmanaged([]const u8) = .empty;
        for (m.params) |param| try texts.append(arena, param.type_text);
        try texts.append(arena, m.return_text);
        for (texts.items) |text| {
            const t = try parseType(p, arena, text, m.class);
            for (t.names) |name| if (!classExists(p, name)) return name;
            for (t.intersections) |group| for (group) |name| if (!classExists(p, name)) return name;
        }
    }
    return "?";
}

// the nearest class above `start` that declares `name`
fn ancestorDeclaring(p: *const Pending, start: ?[]const u8, name: []const u8) ?[]const u8 {
    var current = start;
    while (current) |class| {
        const def = defOf(p, class) orelse return null;
        if (def.methods.getKey(name)) |_| return def.name;
        if (def.is_internal) {
            const key = std.fmt.allocPrint(p.vm.allocator, "{s}::{s}", .{ class, name }) catch return null;
            defer p.vm.allocator.free(key);
            if (p.vm.native_fns.contains(key)) return class;
        }
        current = def.parent;
    }
    return null;
}

fn interfaceMethods(p: *const Pending, iface: []const u8, out: *std.ArrayListUnmanaged([2][]const u8), arena: std.mem.Allocator, seen: *std.StringHashMapUnmanaged(void)) !void {
    if (seen.contains(iface)) return;
    try seen.put(arena, iface, {});
    const idef = p.vm.interfaces.get(iface) orelse return;
    for (idef.parents.items) |parent| try interfaceMethods(p, parent, out, arena, seen);
    if (idef.parent) |parent| try interfaceMethods(p, parent, out, arena, seen);
    for (idef.methods.items) |method| {
        if (std.mem.indexOf(u8, method, "$hook_") != null) continue;
        try out.append(arena, .{ iface, method });
    }
}

// the checks php makes while linking `class_name` (declared as `def`)
pub fn checkClass(vm: *VM, class_name: []const u8, def: *const ClassDef) RuntimeError!void {
    var arena_state = std.heap.ArenaAllocator.init(vm.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var pending: Pending = .{ .vm = vm, .name = class_name, .def = def };
    const p = &pending;

    // methods it declares against the ones its parents declare
    if (def.parent) |parent_name| {
        for (def.method_order.items) |name| {
            if (std.mem.indexOf(u8, name, "$hook_") != null) continue;
            const owner = ancestorDeclaring(p, parent_name, name) orelse continue;
            const parent = (methodOf(p, arena, owner, name, false) catch return error.OutOfMemory) orelse continue;
            const child = (methodOf(p, arena, class_name, name, false) catch return error.OutOfMemory) orelse continue;
            try checkMethod(p, arena, child, parent, std.ascii.eqlIgnoreCase(name, "__construct"));
        }
    }

    // the methods of every interface it implements, against the method that
    // implements each, its own or inherited
    var wanted: std.ArrayListUnmanaged([2][]const u8) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .{};
    for (def.interfaces.items) |iface| interfaceMethods(p, iface, &wanted, arena, &seen) catch return error.OutOfMemory;
    for (wanted.items) |entry| {
        const iface = entry[0];
        const name = entry[1];
        const owner = if (def.methods.getKey(name) != null) class_name else (ancestorDeclaring(p, def.parent, name) orelse continue);
        const child = (methodOf(p, arena, owner, name, false) catch return error.OutOfMemory) orelse continue;
        const proto = (methodOf(p, arena, iface, name, true) catch return error.OutOfMemory) orelse continue;
        try checkMethod(p, arena, child, proto, std.ascii.eqlIgnoreCase(name, "__construct"));
    }
}
