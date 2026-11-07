// php's declared types, as zend_type models them: a mask of built-in types
// plus class names, a union member possibly being an intersection of class
// names. parsed from the type text zphp keeps for a declaration, printed as
// zend_type_to_string_resolved prints them, and compared as
// zend_perform_covariant_type_check compares them

const std = @import("std");

pub const NULL: u32 = 1 << 0;
pub const FALSE: u32 = 1 << 1;
pub const TRUE: u32 = 1 << 2;
pub const LONG: u32 = 1 << 3;
pub const DOUBLE: u32 = 1 << 4;
pub const STRING: u32 = 1 << 5;
pub const ARRAY: u32 = 1 << 6;
pub const OBJECT: u32 = 1 << 7;
pub const RESOURCE: u32 = 1 << 8;
pub const CALLABLE: u32 = 1 << 9;
pub const VOID: u32 = 1 << 10;
pub const NEVER: u32 = 1 << 11;
pub const STATIC: u32 = 1 << 12;
pub const BOOL: u32 = FALSE | TRUE;
// mixed
pub const ANY: u32 = NULL | BOOL | LONG | DOUBLE | STRING | ARRAY | OBJECT | RESOURCE;

pub const Type = struct {
    mask: u32 = 0,
    // single class names of the union, in the order written
    names: []const []const u8 = &.{},
    // intersections of class names, each one member of the union (or the
    // whole type, when `pure_intersection`)
    intersections: []const []const []const u8 = &.{},
    pure_intersection: bool = false,
    // `iterable`, which php compiles to Traversable|array
    iterable: bool = false,

    pub fn isSet(self: Type) bool {
        return self.mask != 0 or self.names.len > 0 or self.intersections.len > 0;
    }

    pub fn deinit(self: Type, allocator: std.mem.Allocator) void {
        allocator.free(self.names);
        for (self.intersections) |group| allocator.free(group);
        allocator.free(self.intersections);
    }
};

const builtins = std.StaticStringMap(u32).initComptime(.{
    .{ "null", NULL },     .{ "false", FALSE },       .{ "true", TRUE },     .{ "bool", BOOL },
    .{ "int", LONG },      .{ "float", DOUBLE },      .{ "string", STRING }, .{ "array", ARRAY },
    .{ "object", OBJECT }, .{ "callable", CALLABLE }, .{ "void", VOID },     .{ "never", NEVER },
    .{ "static", STATIC }, .{ "mixed", ANY },
});

fn builtinBits(name: []const u8) ?u32 {
    var buf: [16]u8 = undefined;
    if (name.len > buf.len) return null;
    return builtins.get(std.ascii.lowerString(&buf, name));
}

// `self` and `parent` resolve against the declaring class, as
// resolve_class_name does; a leading backslash is dropped
fn resolveName(name: []const u8, scope: ?[]const u8, parent: ?[]const u8) []const u8 {
    const bare = if (name.len > 0 and name[0] == '\\') name[1..] else name;
    if (std.ascii.eqlIgnoreCase(bare, "self")) if (scope) |s| return s;
    if (std.ascii.eqlIgnoreCase(bare, "parent")) if (parent) |p| return p;
    return bare;
}

pub fn parse(allocator: std.mem.Allocator, text: []const u8, scope: ?[]const u8, parent: ?[]const u8) !Type {
    var t: Type = .{};
    const trimmed = std.mem.trim(u8, text, " ");
    if (trimmed.len == 0) return t;
    var body = trimmed;
    if (body[0] == '?') {
        t.mask |= NULL;
        body = body[1..];
    }
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer names.deinit(allocator);
    var groups: std.ArrayListUnmanaged([]const []const u8) = .empty;
    errdefer {
        for (groups.items) |g| allocator.free(g);
        groups.deinit(allocator);
    }
    // a type with & and no | or parentheses is a pure intersection
    if (std.mem.indexOfScalar(u8, body, '&') != null and std.mem.indexOfScalar(u8, body, '|') == null and std.mem.indexOfScalar(u8, body, '(') == null) {
        var group: std.ArrayListUnmanaged([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, body, '&');
        while (it.next()) |part| try group.append(allocator, resolveName(std.mem.trim(u8, part, " "), scope, parent));
        try groups.append(allocator, try group.toOwnedSlice(allocator));
        t.pure_intersection = true;
        t.intersections = try groups.toOwnedSlice(allocator);
        return t;
    }
    var it = std.mem.splitScalar(u8, body, '|');
    while (it.next()) |raw| {
        const member = std.mem.trim(u8, raw, " ");
        if (member.len == 0) continue;
        if (member[0] == '(') {
            const inner = std.mem.trim(u8, member, "() ");
            var group: std.ArrayListUnmanaged([]const u8) = .empty;
            var parts = std.mem.splitScalar(u8, inner, '&');
            while (parts.next()) |part| try group.append(allocator, resolveName(std.mem.trim(u8, part, " "), scope, parent));
            try groups.append(allocator, try group.toOwnedSlice(allocator));
            continue;
        }
        if (std.ascii.eqlIgnoreCase(member, "iterable")) {
            t.iterable = true;
            t.mask |= ARRAY;
            try names.append(allocator, "Traversable");
            continue;
        }
        if (builtinBits(member)) |bits| {
            t.mask |= bits;
            continue;
        }
        try names.append(allocator, resolveName(member, scope, parent));
    }
    t.names = try names.toOwnedSlice(allocator);
    t.intersections = try groups.toOwnedSlice(allocator);
    return t;
}

// zend_type_to_string_resolved
pub fn format(allocator: std.mem.Allocator, t: Type) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    var count: usize = 0;
    var has_intersection = false;
    const add = struct {
        fn piece(list: *std.ArrayListUnmanaged(u8), a: std.mem.Allocator, n: *usize, s: []const u8) !void {
            if (n.* > 0) try list.append(a, '|');
            try list.appendSlice(a, s);
            n.* += 1;
        }
    }.piece;
    if (t.pure_intersection) {
        for (t.intersections[0], 0..) |name, i| {
            if (i > 0) try out.append(allocator, '&');
            try out.appendSlice(allocator, name);
        }
        return out.toOwnedSlice(allocator);
    }
    for (t.intersections) |group| {
        var text: std.ArrayListUnmanaged(u8) = .empty;
        defer text.deinit(allocator);
        try text.append(allocator, '(');
        for (group, 0..) |name, i| {
            if (i > 0) try text.append(allocator, '&');
            try text.appendSlice(allocator, name);
        }
        try text.append(allocator, ')');
        try add(&out, allocator, &count, text.items);
        has_intersection = true;
    }
    for (t.names) |name| try add(&out, allocator, &count, name);
    const mask = t.mask;
    if (mask == ANY) {
        try add(&out, allocator, &count, "mixed");
        return out.toOwnedSlice(allocator);
    }
    if (mask & STATIC != 0) try add(&out, allocator, &count, "static");
    if (mask & CALLABLE != 0) try add(&out, allocator, &count, "callable");
    if (mask & OBJECT != 0) try add(&out, allocator, &count, "object");
    if (mask & ARRAY != 0) try add(&out, allocator, &count, "array");
    if (mask & STRING != 0) try add(&out, allocator, &count, "string");
    if (mask & LONG != 0) try add(&out, allocator, &count, "int");
    if (mask & DOUBLE != 0) try add(&out, allocator, &count, "float");
    if (mask & BOOL == BOOL) {
        try add(&out, allocator, &count, "bool");
    } else if (mask & FALSE != 0) {
        try add(&out, allocator, &count, "false");
    } else if (mask & TRUE != 0) {
        try add(&out, allocator, &count, "true");
    }
    if (mask & VOID != 0) try add(&out, allocator, &count, "void");
    if (mask & NEVER != 0) try add(&out, allocator, &count, "never");
    if (mask & NULL != 0) {
        if (count == 1 and !has_intersection) {
            try out.insert(allocator, 0, '?');
        } else try add(&out, allocator, &count, "null");
    }
    return out.toOwnedSlice(allocator);
}

pub const Status = enum { success, failure, unresolved };

// the class questions variance asks: whether a name is a class that can be
// found (loading it if need be), and whether one class is a subtype of another
pub const Classes = struct {
    context: *anyopaque,
    exists: *const fn (*anyopaque, []const u8) bool,
    subtype: *const fn (*anyopaque, []const u8, []const u8) bool,
    is_final: *const fn (*anyopaque, []const u8) bool,

    fn has(self: Classes, name: []const u8) bool {
        return self.exists(self.context, name);
    }
    fn sub(self: Classes, child: []const u8, ancestor: []const u8) bool {
        return self.subtype(self.context, child, ancestor);
    }
};

// zend_type_permits_self
fn permitsSelf(classes: Classes, t: Type, self_scope: []const u8) bool {
    if (t.mask & OBJECT != 0) return true;
    for (t.names) |name| if (classes.has(name) and classes.sub(self_scope, name)) return true;
    return false;
}

// zend_is_class_subtype_of_type: fe_name against a whole proto type
fn classSubtypeOfType(classes: Classes, fe_scope: []const u8, fe_name: []const u8, proto: Type) Status {
    var unresolved = false;
    if (proto.mask & OBJECT != 0) {
        if (classes.has(fe_name)) return .success;
        unresolved = true;
    }
    if (proto.mask & CALLABLE != 0) {
        if (!classes.has(fe_name)) {
            unresolved = true;
        } else if (std.ascii.eqlIgnoreCase(fe_name, "Closure")) return .success;
    }
    if (proto.mask & STATIC != 0 and classes.is_final(classes.context, fe_scope)) {
        if (!classes.has(fe_name)) {
            unresolved = true;
        } else if (std.ascii.eqlIgnoreCase(fe_name, fe_scope)) return .success;
    }
    if (proto.pure_intersection) {
        for (proto.intersections[0]) |name| {
            if (std.ascii.eqlIgnoreCase(fe_name, name)) continue;
            if (!classes.has(fe_name) or !classes.has(name)) {
                unresolved = true;
                continue;
            }
            if (!classes.sub(fe_name, name)) return .failure;
        }
        return if (unresolved) .unresolved else .success;
    }
    for (proto.intersections) |group| {
        const inner: Type = .{ .intersections = &.{group}, .pure_intersection = true };
        switch (classSubtypeOfType(classes, fe_scope, fe_name, inner)) {
            .success => return .success,
            .unresolved => unresolved = true,
            .failure => {},
        }
    }
    for (proto.names) |name| {
        if (std.ascii.eqlIgnoreCase(fe_name, name)) return .success;
        if (!classes.has(fe_name) or !classes.has(name)) {
            unresolved = true;
            continue;
        }
        if (classes.sub(fe_name, name)) return .success;
    }
    return if (unresolved) .unresolved else .failure;
}

// zend_is_intersection_subtype_of_type: an intersection fe member (any one of
// its classes must satisfy each proto requirement)
fn intersectionSubtypeOfType(classes: Classes, group: []const []const u8, proto: Type) Status {
    var unresolved = false;
    if (proto.mask & OBJECT != 0) {
        for (group) |name| {
            if (classes.has(name)) return .success;
            unresolved = true;
        }
    }
    const proto_is_intersection = proto.pure_intersection;
    const early: Status = if (proto_is_intersection) .failure else .success;
    const proto_names: []const []const u8 = if (proto.pure_intersection) proto.intersections[0] else proto.names;
    if (!proto.pure_intersection) for (proto.intersections) |pgroup| {
        const status = intersectionSubtypeOfType(classes, group, .{ .intersections = &.{pgroup}, .pure_intersection = true });
        if (status == early) return status;
        if (status == .unresolved) unresolved = true;
    };
    for (proto_names) |pname| {
        var status: Status = .failure;
        var group_unresolved = false;
        for (group) |name| {
            if (std.ascii.eqlIgnoreCase(name, pname)) {
                status = .success;
                break;
            }
            if (!classes.has(name) or !classes.has(pname)) {
                group_unresolved = true;
                continue;
            }
            if (classes.sub(name, pname)) {
                status = .success;
                break;
            }
        }
        if (status != .success and group_unresolved) status = .unresolved;
        if (status == early) return status;
        if (status == .unresolved) unresolved = true;
    }
    if (unresolved) return .unresolved;
    return if (early == .failure) .success else .failure;
}

// zend_perform_covariant_type_check: is fe (declared in fe_scope) a subtype of
// proto (declared in proto_scope)
pub fn covariant(classes: Classes, fe_scope: []const u8, fe: Type, proto: Type) Status {
    if (proto.mask == ANY and proto.names.len == 0 and proto.intersections.len == 0 and fe.mask & VOID == 0) return .success;
    var added = fe.mask & ~proto.mask;
    if (added != 0) {
        if (added & STATIC != 0 and permitsSelf(classes, proto, fe_scope)) added &= ~STATIC;
        if (added == NEVER) return .success;
        if (added != 0) return .failure;
    }
    var unresolved = false;
    if (fe.pure_intersection) {
        const early: Status = if (proto.pure_intersection) .failure else .success;
        const status = intersectionSubtypeOfType(classes, fe.intersections[0], proto);
        if (status == early) return status;
        if (status == .unresolved) unresolved = true;
        if (unresolved) return .unresolved;
        return if (early == .failure) .success else .failure;
    }
    for (fe.intersections) |group| {
        const status = intersectionSubtypeOfType(classes, group, proto);
        if (status == .failure) return .failure;
        if (status == .unresolved) unresolved = true;
    }
    for (fe.names) |name| {
        const status = classSubtypeOfType(classes, fe_scope, name, proto);
        if (status == .failure) return .failure;
        if (status == .unresolved) unresolved = true;
    }
    return if (unresolved) .unresolved else .success;
}
