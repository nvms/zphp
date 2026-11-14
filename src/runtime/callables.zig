// what a callable value calls, decided the way php decides it. php has two
// sets of rules: a callback handed to an internal function (call_user_func,
// usort, a `callable` parameter) follows zend_is_callable, which knows the
// caller's scope (self::, parent::, static::, private methods, a $this to call
// an instance method through); a value called directly (`$f()`) follows
// zend_init_dynamic_call, which knows none of that. both fall back to
// __call/__callStatic for a method the class lacks, and both report a value
// they can't call in php's words

const std = @import("std");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const ClassDef = vm_mod.ClassDef;
const RuntimeError = vm_mod.RuntimeError;
const Value = @import("value.zig").Value;
const PhpObject = @import("value.zig").PhpObject;
const PhpArray = @import("value.zig").PhpArray;

pub const Callee = union(enum) {
    // a function or closure name
    function: []const u8,
    // a Closure object
    closure: *PhpObject,
    // an object called through __invoke
    invoke: *PhpObject,
    // an instance method, by the name it was asked for. registered is the
    // method found in a class the callable names, which is called even when
    // the object's class overrides it
    method: struct { object: *PhpObject, name: []const u8, registered: ?[]const u8 = null },
    // a static method by its registered "Class::method", and the class
    // static:: names inside it
    static_method: struct { registered: []const u8, called_class: []const u8 },
    // a method the class lacks: __call on the object, else __callStatic on
    // the class
    magic: struct { object: ?*PhpObject, class: []const u8, name: []const u8 },
};

pub const Failure = union(enum) {
    not_callable: Value,
    array_count,
    array_indices,
    first_member,
    second_member,
    invalid_function_name,
    no_scope: []const u8,
    no_parent,
    class_not_found: []const u8,
    function_not_found: []const u8,
    method_not_found: struct { class: []const u8, method: []const u8 },
    not_subclass: struct { class: []const u8, of: []const u8 },
    non_static: struct { class: []const u8, method: []const u8 },
    abstract_method: struct { class: []const u8, method: []const u8 },
    // direct: the method itself, which a callback checked from another scope
    // still calls
    inaccessible: struct { visibility: ClassDef.Visibility, class: []const u8, method: []const u8, scope: ?[]const u8, direct: Callee },
};

pub const Resolution = union(enum) {
    callee: Callee,
    failure: Failure,
};

pub const CallbackRules = struct {
    // "Use of "self" in callables is deprecated" and the like; a callable
    // already checked once (a native's callable parameter) stays quiet
    deprecations: bool = true,
};

// zend_is_callable: a callback as an internal function receives it, resolved
// against the calling scope. an autoloader or a deprecation handler that
// throws leaves its exception pending
pub fn resolveCallback(vm: *VM, callable: Value, rules: CallbackRules) RuntimeError!Resolution {
    switch (callable) {
        .string => |s| return resolveCallbackString(vm, s.bytes(), null, rules),
        .object => |obj| return if (objectCallee(vm, obj)) |callee| .{ .callee = callee } else .{ .failure = .{ .not_callable = callable } },
        .array => |arr| {
            if (arr.entries.items.len != 2) return .{ .failure = .array_count };
            if (!arr.contains(.{ .int = 0 }) or !arr.contains(.{ .int = 1 })) return .{ .failure = .array_indices };
            const target = arr.get(.{ .int = 0 });
            const method = arr.get(.{ .int = 1 });
            if (target != .string and target != .object) return .{ .failure = .first_member };
            if (method != .string) return .{ .failure = .second_member };
            var site: Site = .{};
            if (target == .object) {
                site.calling = target.object.class_name;
                site.called = target.object.class_name;
                site.object = target.object;
            } else if (try checkClass(vm, target.string.bytes(), &site, rules)) |failure| {
                return .{ .failure = failure };
            }
            return resolveCallbackString(vm, method.string.bytes(), site, rules);
        },
        else => return .{ .failure = .{ .not_callable = callable } },
    }
}

// where a callback's method is looked up: the class it was named on, the
// class static:: names, and the object it is called on
const Site = struct {
    calling: ?[]const u8 = null,
    called: ?[]const u8 = null,
    object: ?*PhpObject = null,
    // named by class rather than reached through the object
    strict: bool = false,
};

fn resolveCallbackString(vm: *VM, name: []const u8, given_site: ?Site, rules: CallbackRules) RuntimeError!Resolution {
    var site = given_site orelse Site{};
    const origin = site.calling;
    if (origin == null) {
        if (functionNamed(vm, name)) |registered| return .{ .callee = .{ .function = registered } };
    }
    var method = name;
    if (memberSeparator(name)) |sep| {
        if (sep == 0) return .{ .failure = .invalid_function_name };
        const class_part = name[0..sep];
        method = name[sep + 2 ..];
        // ["Child", "parent::method"]: the class part is resolved from the
        // first member's class
        if (try checkClassFrom(vm, class_part, origin, &site, .{ .deprecations = rules.deprecations and origin == null })) |failure| return .{ .failure = failure };
        if (origin) |org| {
            if (!vm.isInstanceOf(org, site.calling.?)) return .{ .failure = .{ .not_subclass = .{ .class = org, .of = site.calling.? } } };
            if (rules.deprecations) {
                const msg = try std.fmt.allocPrint(vm.allocator, "Callables of the form [\"{s}\", \"{s}\"] are deprecated", .{ org, name });
                defer vm.allocator.free(msg);
                try vm.raiseError(VM.E_DEPRECATED, msg);
            }
        }
    } else if (origin == null) {
        return .{ .failure = .{ .function_not_found = name } };
    }
    return resolveMethod(vm, &site, method, origin);
}

// the method half of zend_is_callable_check_func, once the class is known
fn resolveMethod(vm: *VM, site: *Site, method: []const u8, origin: ?[]const u8) RuntimeError!Resolution {
    const calling = site.calling.?;
    const scope = vm.currentDefiningClass();
    var via_handler = false;
    var found: ?Method = null;
    if (try findMethod(vm, calling, method)) |m| {
        found = m;
        // an inaccessible method gives way to the magic method that would
        // take the call
        if (m.visibility != .public and !vm.checkVisibility(m.class, m.visibility)) {
            const magic: []const u8 = if (site.object != null) "__call" else "__callStatic";
            if (vm.hasMethod(calling, magic)) via_handler = true;
        }
    } else via_handler = true;

    if (via_handler) {
        const magic = magicFor(vm, site, origin) orelse {
            return .{ .failure = .{ .method_not_found = .{ .class = vm.declaredClassName(calling), .method = method } } };
        };
        return .{ .callee = magic.callee(method) };
    }

    const m = found.?;
    if (m.is_abstract) return .{ .failure = .{ .abstract_method = .{ .class = vm.declaredClassName(calling), .method = m.name } } };
    if (site.object == null and m.is_static == false) return .{ .failure = .{ .non_static = .{ .class = vm.declaredClassName(calling), .method = m.name } } };
    const static_call = if (m.is_static) |is_static| is_static else site.object == null;
    const callee: Callee = if (static_call)
        .{ .static_method = .{ .registered = m.registered, .called_class = if (site.object) |obj| obj.class_name else site.called orelse calling } }
    else
        .{ .method = .{ .object = site.object.?, .name = m.name, .registered = if (std.mem.eql(u8, calling, site.object.?.class_name)) null else m.registered } };
    if (m.visibility != .public and !vm.checkVisibility(m.class, m.visibility)) {
        return .{ .failure = .{ .inaccessible = .{ .visibility = m.visibility, .class = vm.declaredClassName(calling), .method = m.name, .scope = scope, .direct = callee } } };
    }
    return .{ .callee = callee };
}

const Magic = struct {
    object: ?*PhpObject,
    class: []const u8,

    fn callee(self: Magic, method: []const u8) Callee {
        return .{ .magic = .{ .object = self.object, .class = self.class, .name = method } };
    }
};

// get_method/get_static_method's fallback: __call for an object (or for the
// running $this when it is an instance of the class), else __callStatic
fn magicFor(vm: *VM, site: *Site, origin: ?[]const u8) ?Magic {
    const calling = site.calling.?;
    if (site.object) |obj| {
        if (origin != null and std.mem.eql(u8, origin.?, calling) and !site.strict) {
            if (vm.hasMethod(obj.class_name, "__call")) return .{ .object = obj, .class = obj.class_name };
            return null;
        }
    }
    if (vm.hasMethod(calling, "__call")) {
        if (vm.scopeThis()) |this| if (vm.isInstanceOf(this.class_name, calling)) {
            return .{ .object = this, .class = this.class_name };
        };
    }
    if (vm.hasMethod(calling, "__callStatic")) return .{ .object = null, .class = calling };
    return null;
}

fn checkClass(vm: *VM, name: []const u8, site: *Site, rules: CallbackRules) RuntimeError!?Failure {
    return checkClassFrom(vm, name, null, site, rules);
}

// zend_is_callable_check_class: self, parent and static from the calling
// scope, any other name looked up (autoloading), and the running $this taken
// as the object when it belongs to that class
fn checkClassFrom(vm: *VM, name: []const u8, origin: ?[]const u8, site: *Site, rules: CallbackRules) RuntimeError!?Failure {
    const scope = if (origin) |org| org else vm.currentDefiningClass();
    const called_scope = calledScope(vm);
    site.strict = false;
    if (std.ascii.eqlIgnoreCase(name, "self")) {
        const s = scope orelse return .{ .no_scope = "self" };
        try deprecateScopeWord(vm, "self", rules);
        site.called = if (called_scope) |c| if (vm.isInstanceOf(c, s)) c else s else s;
        site.calling = s;
        if (site.object == null) site.object = vm.scopeThis();
    } else if (std.ascii.eqlIgnoreCase(name, "parent")) {
        const s = scope orelse return .{ .no_scope = "parent" };
        const parent = (vm.classes.get(s) orelse return .no_parent).parent orelse return .no_parent;
        try deprecateScopeWord(vm, "parent", rules);
        site.called = if (called_scope) |c| if (vm.isInstanceOf(c, parent)) c else parent else parent;
        site.calling = parent;
        if (site.object == null) site.object = vm.scopeThis();
        site.strict = true;
    } else if (std.ascii.eqlIgnoreCase(name, "static")) {
        const c = called_scope orelse return .{ .no_scope = "static" };
        try deprecateScopeWord(vm, "static", rules);
        site.called = c;
        site.calling = c;
        if (site.object == null) site.object = vm.scopeThis();
        site.strict = true;
    } else {
        const class = (try lookupClass(vm, name)) orelse return .{ .class_not_found = name };
        site.calling = class;
        const this_scope = vm.currentDefiningClass();
        if (this_scope != null and site.object == null) {
            const this = vm.scopeThis();
            if (this != null and vm.isInstanceOf(this.?.class_name, this_scope.?) and vm.isInstanceOf(this_scope.?, class)) {
                site.object = this;
                site.called = this.?.class_name;
            } else site.called = class;
        } else site.called = if (site.object) |obj| obj.class_name else class;
        site.strict = true;
    }
    return null;
}

fn deprecateScopeWord(vm: *VM, word: []const u8, rules: CallbackRules) RuntimeError!void {
    if (!rules.deprecations) return;
    const msg = try std.fmt.allocPrint(vm.allocator, "Use of \"{s}\" in callables is deprecated", .{word});
    defer vm.allocator.free(msg);
    try vm.raiseError(VM.E_DEPRECATED, msg);
}

pub fn calledScope(vm: *VM) ?[]const u8 {
    if (vm.frame_count > 0) if (vm.currentFrame().called_class) |c| return c;
    return vm.currentDefiningClass();
}

// zend_init_dynamic_call: `$f()` on a string, array, or object
pub fn resolveDynamic(vm: *VM, callable: Value) RuntimeError!Resolution {
    switch (callable) {
        .string => |str| {
            const name = str.bytes();
            if (memberSeparator(name)) |sep| {
                const class = (try lookupClass(vm, name[0..sep])) orelse return .{ .failure = .{ .class_not_found = name[0..sep] } };
                return staticCallee(vm, class, name[sep + 2 ..]);
            }
            if (functionNamed(vm, name)) |registered| return .{ .callee = .{ .function = registered } };
            return .{ .failure = .{ .function_not_found = name } };
        },
        .object => |obj| return if (objectCallee(vm, obj)) |callee| .{ .callee = callee } else .{ .failure = .{ .not_callable = callable } },
        .array => |arr| {
            if (arr.entries.items.len != 2) return .{ .failure = .array_count };
            if (!arr.contains(.{ .int = 0 }) or !arr.contains(.{ .int = 1 })) return .{ .failure = .array_indices };
            const target = arr.get(.{ .int = 0 });
            const method = arr.get(.{ .int = 1 });
            if (target != .string and target != .object) return .{ .failure = .first_member };
            if (method != .string) return .{ .failure = .second_member };
            if (target == .string) {
                const class = (try lookupClass(vm, target.string.bytes())) orelse return .{ .failure = .{ .class_not_found = target.string.bytes() } };
                return staticCallee(vm, class, method.string.bytes());
            }
            return instanceCallee(vm, target.object, method.string.bytes());
        },
        else => return .{ .failure = .{ .not_callable = callable } },
    }
}

// zend_std_get_static_method, then the static check the dynamic call makes
fn staticCallee(vm: *VM, class: []const u8, method: []const u8) RuntimeError!Resolution {
    const scope = vm.currentDefiningClass();
    if (try findMethod(vm, class, method)) |m| {
        if (m.visibility == .public or vm.checkVisibility(m.class, m.visibility)) {
            if (m.is_static == false) return .{ .failure = .{ .non_static = .{ .class = vm.declaredClassName(m.class), .method = m.name } } };
            return .{ .callee = .{ .static_method = .{ .registered = m.registered, .called_class = class } } };
        }
        if (staticFallback(vm, class)) |magic| return magicStatic(vm, magic, method);
        const direct: Callee = .{ .static_method = .{ .registered = m.registered, .called_class = class } };
        return .{ .failure = .{ .inaccessible = .{ .visibility = m.visibility, .class = vm.declaredClassName(m.class), .method = m.name, .scope = scope, .direct = direct } } };
    }
    if (staticFallback(vm, class)) |magic| return magicStatic(vm, magic, method);
    return .{ .failure = .{ .method_not_found = .{ .class = vm.declaredClassName(class), .method = method } } };
}

// __call through the running $this is an instance call, which a dynamic
// static call refuses
fn magicStatic(vm: *VM, magic: Magic, method: []const u8) Resolution {
    if (magic.object != null) return .{ .failure = .{ .non_static = .{ .class = vm.declaredClassName(magic.class), .method = method } } };
    return .{ .callee = magic.callee(method) };
}

fn staticFallback(vm: *VM, class: []const u8) ?Magic {
    if (vm.hasMethod(class, "__call")) {
        if (vm.scopeThis()) |this| if (vm.isInstanceOf(this.class_name, class)) return .{ .object = this, .class = this.class_name };
    }
    if (vm.hasMethod(class, "__callStatic")) return .{ .object = null, .class = class };
    return null;
}

// zend_std_get_method
fn instanceCallee(vm: *VM, obj: *PhpObject, method: []const u8) RuntimeError!Resolution {
    const scope = vm.currentDefiningClass();
    if (try findMethod(vm, obj.class_name, method)) |m| {
        if (m.visibility == .public or vm.checkVisibility(m.class, m.visibility)) {
            if (m.is_static == true) return .{ .callee = .{ .static_method = .{ .registered = m.registered, .called_class = obj.class_name } } };
            return .{ .callee = .{ .method = .{ .object = obj, .name = m.name } } };
        }
        if (vm.hasMethod(obj.class_name, "__call")) return .{ .callee = .{ .magic = .{ .object = obj, .class = obj.class_name, .name = method } } };
        const direct: Callee = .{ .method = .{ .object = obj, .name = m.name } };
        return .{ .failure = .{ .inaccessible = .{ .visibility = m.visibility, .class = vm.declaredClassName(m.class), .method = m.name, .scope = scope, .direct = direct } } };
    }
    if (vm.hasMethod(obj.class_name, "__call")) return .{ .callee = .{ .magic = .{ .object = obj, .class = obj.class_name, .name = method } } };
    return .{ .failure = .{ .method_not_found = .{ .class = obj.class_name, .method = method } } };
}

fn objectCallee(vm: *VM, obj: *PhpObject) ?Callee {
    if (std.mem.eql(u8, obj.class_name, "Closure")) return .{ .closure = obj };
    if (vm.hasMethod(obj.class_name, "__invoke")) return .{ .invoke = obj };
    return null;
}

// the position of "::" in "Class::method", found from the right as php does
fn memberSeparator(name: []const u8) ?usize {
    const colon = std.mem.lastIndexOfScalar(u8, name, ':') orelse return null;
    if (colon == 0 or name[colon - 1] != ':') return null;
    return colon - 1;
}

// methods share the function tables as "Class::method", so a name with "::"
// is never a function
fn functionNamed(vm: *VM, raw: []const u8) ?[]const u8 {
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    if (name.len == 0 or std.mem.indexOf(u8, name, "::") != null) return null;
    if (VM.isLanguageConstruct(name)) return null;
    if (vm.native_fns.getKey(name)) |key| return key;
    if (vm.functions.getKey(name)) |key| return key;
    return vm.functionNamedIgnoringCase(name);
}

fn lookupClass(vm: *VM, raw: []const u8) RuntimeError!?[]const u8 {
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    if (vm.classes.getKey(name)) |key| return key;
    try vm.tryAutoload(name);
    if (vm.pending_exception != null) return error.RuntimeError;
    return vm.classes.getKey(name);
}

const Method = struct {
    // the declaring class and the method as declared
    class: []const u8,
    name: []const u8,
    registered: []const u8,
    visibility: ClassDef.Visibility,
    // null for a native method whose class didn't record it
    is_static: ?bool,
    is_abstract: bool,
};

fn findMethod(vm: *VM, class: []const u8, method: []const u8) RuntimeError!?Method {
    const registered = vm.resolveMethod(class, method) catch {
        if (vm.pending_exception != null) return error.RuntimeError;
        return null;
    };
    const sep = std.mem.indexOf(u8, registered, "::").?;
    const declaring = registered[0..sep];
    const name = registered[sep + 2 ..];
    const info: ?ClassDef.MethodInfo = if (vm.classes.get(declaring)) |cls| cls.methods.get(name) else null;
    return .{
        .class = declaring,
        .name = name,
        .registered = registered,
        .visibility = if (info) |i| i.visibility else .public,
        .is_static = if (info) |i| i.is_static else null,
        // an interface's methods are all abstract
        .is_abstract = if (info) |i| i.is_abstract else vm.interfaces.contains(declaring),
    };
}

pub fn invoke(vm: *VM, callee: Callee, args: []const Value) RuntimeError!Value {
    switch (callee) {
        .function => |name| return vm.callByName(name, args),
        .closure => |obj| {
            if (obj.closureName()) |name| return vm.callByName(name, args);
            const state = obj.fakeClosure() orelse return .null;
            var target = try vm.callbackCallee(state.callable);
            // made through self:: or parent::, a static method keeps the
            // class static:: named where it was made
            if (state.called_class) |called| if (target == .static_method) {
                target.static_method.called_class = called;
            };
            return invoke(vm, target, args);
        },
        .invoke => |obj| return vm.callMethod(obj, "__invoke", args),
        .method => |m| return vm.callMethodAs(m.object, m.name, m.registered, args),
        .static_method => |m| return vm.callByNameAs(m.registered, args, m.called_class),
        .magic => |m| {
            const packed_args = try vm.allocArray();
            for (args) |arg| try packed_args.append(vm.allocator, arg);
            // a transient copy: __call may return the name, which then
            // outlives whatever callable it came from
            const magic_args = [_]Value{ .{ .string = try vm.transientBytes(m.name) }, .{ .array = packed_args } };
            if (m.object) |obj| return vm.callTrampoline(obj, &magic_args);
            const registered = try vm.resolveMethod(m.class, "__callStatic");
            return vm.callByNameAs(registered, &magic_args, m.class);
        },
    }
}

// zend_call_function with named_params: an argument array whose integer keys
// are positional arguments and whose string keys name parameters. a name
// lands on its parameter (zend_handle_named_arg), names no parameter has go
// to a variadic or are an Error, a trampoline (__call, __callStatic) gets
// them as keys of its argument array, and a skipped parameter takes its
// default or is php's "not passed" (zend_handle_undef_args)
pub fn invokeArgArray(vm: *VM, callee: Callee, arr: *PhpArray) RuntimeError!Value {
    return invokeArgArrayFrom(vm, callee, arr, false);
}

// from_native: an internal function makes the call (call_user_func), so a
// by-reference parameter given a value warns as zend_call_function does
pub fn invokeArgArrayFrom(vm: *VM, callee: Callee, arr: *PhpArray, from_native: bool) RuntimeError!Value {
    var named = false;
    for (arr.entries.items) |entry| {
        if (entry.key == .string) {
            named = true;
        } else if (named) {
            try vm.setPendingException("Error", "Cannot use positional argument after named argument");
            return error.RuntimeError;
        }
    }
    if (!named) {
        var buf: [16]Value = undefined;
        const args = if (arr.entries.items.len <= buf.len) buf[0..arr.entries.items.len] else try vm.allocator.alloc(Value, arr.entries.items.len);
        defer if (args.ptr != &buf) vm.allocator.free(args);
        for (arr.entries.items, args) |entry, *arg| arg.* = if (entry.ref) |cell| cell.* else entry.value;
        return invoke(vm, callee, args);
    }
    switch (callee) {
        .magic => |m| {
            // positional arguments, then the named ones under their names
            const packed_args = try vm.allocArray();
            for (arr.entries.items) |entry| {
                const v = if (entry.ref) |cell| cell.* else entry.value;
                if (entry.key == .string) try packed_args.set(vm.allocator, entry.key, v) else try packed_args.append(vm.allocator, v);
            }
            const magic_args = [_]Value{ .{ .string = try vm.transientBytes(m.name) }, .{ .array = packed_args } };
            if (m.object) |obj| return vm.callTrampoline(obj, &magic_args);
            const registered = try vm.resolveMethod(m.class, "__callStatic");
            return vm.callByNameAs(registered, &magic_args, m.class);
        },
        .closure => |obj| {
            if (obj.closureName() == null) {
                const state = obj.fakeClosure() orelse return .null;
                var target = try vm.callbackCallee(state.callable);
                if (state.called_class) |called| if (target == .static_method) {
                    target.static_method.called_class = called;
                };
                return invokeArgArrayFrom(vm, target, arr, from_native);
            }
        },
        else => {},
    }
    // the function the call reaches, by its registered name
    const name: []const u8 = switch (callee) {
        .function => |n| n,
        .closure => |obj| obj.closureName().?,
        .invoke => |obj| try vm.resolveMethod(obj.class_name, "__invoke"),
        .method => |m| m.registered orelse try vm.resolveMethod(m.object.class_name, m.name),
        .static_method => |m| m.registered,
        .magic => unreachable,
    };
    if (vm.functions.get(name)) |func| {
        const bound = try bindNamed(vm, name, func, arr) orelse return error.RuntimeError;
        defer bound.deinit(vm.allocator);
        if (from_native) for (bound.origins[0..bound.count], 0..) |origin, i| {
            if (i >= func.ref_params.len or !func.ref_params[i] or i >= func.params.len) continue;
            if (origin) |ei| if (arr.entries.items[ei].ref != null) continue;
            const shown = try vm.callableDisplayName(name, func);
            const param = func.params[i];
            const msg = try std.fmt.allocPrint(vm.allocator, "{s}(): Argument #{d} (${s}) must be passed by reference, value given", .{ shown, i + 1, if (param.len > 0 and param[0] == '$') param[1..] else param });
            defer vm.allocator.free(msg);
            try vm.emitWarning(msg);
        };
        // names a variadic collects, for the frame to add to it
        vm.pending_named_extras = bound.extras;
        defer vm.pending_named_extras = null;
        const values = bound.args();
        return switch (callee) {
            .function => |n| vm.callByName(n, values),
            .closure => |obj| vm.callByName(obj.closureName().?, values),
            .invoke => |obj| vm.callMethodAs(obj, "__invoke", name, values),
            .method => |m| vm.callMethodAs(m.object, m.name, m.registered, values),
            .static_method => |m| vm.callByNameAs(m.registered, values, m.called_class),
            .magic => unreachable,
        };
    }
    const native_params = @import("../stdlib/native_params.zig");
    const signature = native_params.get(name) orelse {
        // a native with no known parameter list takes the values in order
        var buf: [16]Value = undefined;
        const args = if (arr.entries.items.len <= buf.len) buf[0..arr.entries.items.len] else try vm.allocator.alloc(Value, arr.entries.items.len);
        defer if (args.ptr != &buf) vm.allocator.free(args);
        for (arr.entries.items, args) |entry, *arg| arg.* = if (entry.ref) |cell| cell.* else entry.value;
        return invoke(vm, callee, args);
    };
    var resolved: [256]Value = undefined;
    var sources: [256]vm_mod.RefSource = undefined;
    const placed = try vm.placeNativeNamedArgs(arr, signature.params, &resolved, &sources, @import("natives.zig").acceptsNamedExtras(name));
    if (placed.problem) |problem| {
        const class: []const u8, const msg = try vm.namedArgProblemMessage(name, signature.params, problem);
        defer vm.allocator.free(msg);
        vm.discardNativeNamedArgs();
        try vm.setPendingException(class, msg);
        return error.RuntimeError;
    }
    if (from_native) {
        // an internal function's by-reference parameter given a value
        const byref = @import("../stdlib/byref_args.zig");
        for (0..placed.count) |i| {
            if (!byref.isByRef(name, i)) continue;
            if (std.ascii.eqlIgnoreCase(name, "array_multisort") or std.ascii.eqlIgnoreCase(name, "extract")) continue;
            const text = try vm.cannotPassByReference(name, @intCast(@min(i, 255)));
            defer vm.allocator.free(text);
            const suffix = " could not be passed by reference";
            const head = if (std.mem.endsWith(u8, text, suffix)) text[0 .. text.len - suffix.len] else text;
            const msg = try std.fmt.allocPrint(vm.allocator, "{s} must be passed by reference, value given", .{head});
            defer vm.allocator.free(msg);
            try vm.emitWarning(msg);
        }
    }
    return invoke(vm, callee, resolved[0..placed.count]);
}

pub const Bound = struct {
    // the arguments in parameter order, count of them used
    values: []Value,
    // the argument array entry each came from, null for a default
    origins: []?usize,
    count: usize,
    // named arguments matching no parameter, for the variadic
    extras: ?*PhpArray,

    pub fn args(self: Bound) []Value {
        return self.values[0..self.count];
    }

    pub fn deinit(self: Bound, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        allocator.free(self.origins);
    }
};

// zend_handle_named_arg and zend_handle_undef_args for a user function: the
// arguments an argument array with names gives each parameter, or null with
// php's Error pending
pub fn bindNamed(vm: *VM, name: []const u8, func: *const @import("../pipeline/bytecode.zig").ObjFunction, arr: *PhpArray) RuntimeError!?Bound {
    const slots = func.params.len + arr.entries.items.len;
    const values = try vm.allocator.alloc(Value, slots);
    var keep = false;
    defer if (!keep) vm.allocator.free(values);
    const origins = try vm.allocator.alloc(?usize, slots);
    defer if (!keep) vm.allocator.free(origins);
    @memset(values, .null);
    @memset(origins, null);
    // a variadic's own parameter takes no name: names matching nothing else
    // are its keyed entries
    const fixed: usize = if (func.is_variadic and func.arity > 0) func.arity - 1 else func.params.len;
    var extras: ?*PhpArray = null;
    var count: usize = 0;
    var position: usize = 0;
    for (arr.entries.items, 0..) |entry, ei| {
        const v = if (entry.ref) |cell| cell.* else entry.value;
        if (entry.key == .int) {
            values[position] = v;
            origins[position] = ei;
            position += 1;
            count = @max(count, position);
            continue;
        }
        const key = entry.key.string.bytes();
        const index = for (func.params[0..fixed], 0..) |p, pi| {
            if (std.mem.eql(u8, if (p.len > 0 and p[0] == '$') p[1..] else p, key)) break pi;
        } else null;
        if (index) |i| {
            if (origins[i] != null) {
                const msg = try std.fmt.allocPrint(vm.allocator, "Named parameter ${s} overwrites previous argument", .{key});
                defer vm.allocator.free(msg);
                try vm.setPendingException("Error", msg);
                return null;
            }
            values[i] = v;
            origins[i] = ei;
            count = @max(count, i + 1);
            continue;
        }
        if (!func.is_variadic) {
            const msg = try std.fmt.allocPrint(vm.allocator, "Unknown named parameter ${s}", .{key});
            defer vm.allocator.free(msg);
            try vm.setPendingException("Error", msg);
            return null;
        }
        // checked against the variadic's type, coerced in weak mode
        var ev = v;
        const vtype: []const u8 = blk: {
            const ti = vm.typeInfoFor(name) orelse break :blk "";
            const vi = func.arity - 1;
            break :blk if (vi < ti.param_types.len) ti.param_types[vi] else "";
        };
        if (vtype.len > 0 and !vm.checkTypeMatch(ev, vtype)) {
            const strict = if (vm.frame_count >= 1) (if (vm.currentFrame().func) |cf| cf.strict_types else vm.script_strict_types) else vm.script_strict_types;
            const coerced = if (strict) null else try vm.tryWeakCoerce(ev, vtype);
            if (coerced) |c| ev = c else {
                const msg = try std.fmt.allocPrint(vm.allocator, "{s}(): Argument ${s} must be of type {s}, {s} given", .{ name, key, vtype, VM.valueTypeName(ev) });
                defer vm.allocator.free(msg);
                try vm.setPendingException("TypeError", msg);
                return null;
            }
        }
        if (extras == null) extras = try vm.allocArray();
        try extras.?.set(vm.allocator, entry.key, ev);
    }
    // a skipped parameter before the last one passed takes its default; one
    // before a required parameter has none (its default is ignored)
    for (0..count) |i| {
        if (origins[i] != null) continue;
        if (i < func.defaults.len and i >= func.required_params) {
            values[i] = try vm.resolveParamDefault(func, i);
            continue;
        }
        const shown = try vm.callableDisplayName(name, func);
        const param = func.params[i];
        const msg = try std.fmt.allocPrint(vm.allocator, "{s}(): Argument #{d} (${s}) not passed", .{ shown, i + 1, if (param.len > 0 and param[0] == '$') param[1..] else param });
        defer vm.allocator.free(msg);
        try vm.setPendingException("ArgumentCountError", msg);
        return null;
    }
    keep = true;
    return .{ .values = values, .origins = origins, .count = count, .extras = extras };
}

// as invoke, writing by-reference parameters back into args
pub fn invokeRef(vm: *VM, callee: Callee, args: []Value) RuntimeError!Value {
    switch (callee) {
        .function => |name| return vm.callByNameRef(name, args),
        .invoke => |obj| return vm.callMethodRef(obj, "__invoke", args),
        .method => |m| return vm.callMethodRefAs(m.object, m.name, m.registered, args),
        .static_method => |m| return vm.callByNameRefAs(m.registered, args, m.called_class),
        .closure => |obj| {
            if (obj.closureName()) |name| return vm.callByNameRef(name, args);
            return invoke(vm, callee, args);
        },
        .magic => return invoke(vm, callee, args),
    }
}

// zend_get_callable_name: how php names a callable in an error
pub fn writeName(callable: Value, buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    switch (callable) {
        .string => |s| try buf.appendSlice(allocator, s.bytes()),
        .array => |arr| {
            const target = arr.get(.{ .int = 0 });
            const method = arr.get(.{ .int = 1 });
            if (arr.entries.items.len != 2 or method != .string) return buf.appendSlice(allocator, "Array");
            switch (target) {
                .string => |s| try buf.print(allocator, "{s}::{s}", .{ s.bytes(), method.string.bytes() }),
                .object => |o| try buf.print(allocator, "{s}::{s}", .{ o.class_name, method.string.bytes() }),
                else => try buf.appendSlice(allocator, "Array"),
            }
        },
        .object => |o| if (std.mem.eql(u8, o.class_name, "Closure"))
            try buf.appendSlice(allocator, "{closure}")
        else
            try buf.print(allocator, "{s}::__invoke", .{o.class_name}),
        .int => |i| try buf.print(allocator, "{d}", .{i}),
        .bool => |b| try buf.appendSlice(allocator, if (b) "1" else ""),
        else => {},
    }
}

// zend_is_callable's error text, which follows "must be a valid callback, "
pub fn writeReason(failure: Failure, buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
    switch (failure) {
        .not_callable => try buf.appendSlice(allocator, "no array or string given"),
        .array_count => try buf.appendSlice(allocator, "array callback must have exactly two members"),
        .array_indices => try buf.appendSlice(allocator, "array callback has to contain indices 0 and 1"),
        .first_member => try buf.appendSlice(allocator, "first array member is not a valid class name or object"),
        .second_member => try buf.appendSlice(allocator, "second array member is not a valid method"),
        .invalid_function_name => try buf.appendSlice(allocator, "invalid function name"),
        .no_scope => |word| try buf.print(allocator, "cannot access \"{s}\" when no class scope is active", .{word}),
        .no_parent => try buf.appendSlice(allocator, "cannot access \"parent\" when current class scope has no parent"),
        .class_not_found => |name| try buf.print(allocator, "class \"{s}\" not found", .{name}),
        .function_not_found => |name| try buf.print(allocator, "function \"{s}\" not found or invalid function name", .{name}),
        .method_not_found => |m| try buf.print(allocator, "class {s} does not have a method \"{s}\"", .{ m.class, m.method }),
        .not_subclass => |m| try buf.print(allocator, "class {s} is not a subclass of {s}", .{ m.class, m.of }),
        .non_static => |m| try buf.print(allocator, "non-static method {s}::{s}() cannot be called statically", .{ m.class, m.method }),
        .abstract_method => |m| try buf.print(allocator, "cannot call abstract method {s}::{s}()", .{ m.class, m.method }),
        .inaccessible => |m| try buf.print(allocator, "cannot access {s} method {s}::{s}()", .{ visibilityName(m.visibility), m.class, m.method }),
    }
}

// the Error a dynamic call raises for a value it can't call
pub fn throwDynamicFailure(vm: *VM, failure: Failure) RuntimeError!bool {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(vm.allocator);
    const a = vm.allocator;
    switch (failure) {
        .not_callable => |v| if (v == .object)
            try buf.print(a, "Object of type {s} is not callable", .{v.object.class_name})
        else
            try buf.print(a, "Value of type {s} is not callable", .{v.valueName()}),
        .array_count => try buf.appendSlice(a, "Array callback must have exactly two elements"),
        .array_indices => try buf.appendSlice(a, "Array callback has to contain indices 0 and 1"),
        .first_member => try buf.appendSlice(a, "First array member is not a valid class name or object"),
        .second_member => try buf.appendSlice(a, "Second array member is not a valid method"),
        .class_not_found => |name| try buf.print(a, "Class \"{s}\" not found", .{name}),
        .function_not_found => |name| try buf.print(a, "Call to undefined function {s}()", .{name}),
        .method_not_found => |m| try buf.print(a, "Call to undefined method {s}::{s}()", .{ m.class, m.method }),
        .non_static => |m| try buf.print(a, "Non-static method {s}::{s}() cannot be called statically", .{ m.class, m.method }),
        .abstract_method => |m| try buf.print(a, "Cannot call abstract method {s}::{s}()", .{ m.class, m.method }),
        .inaccessible => |m| if (m.scope) |scope|
            try buf.print(a, "Call to {s} method {s}::{s}() from scope {s}", .{ visibilityName(m.visibility), m.class, m.method, scope })
        else
            try buf.print(a, "Call to {s} method {s}::{s}() from global scope", .{ visibilityName(m.visibility), m.class, m.method }),
        .invalid_function_name, .no_scope, .no_parent, .not_subclass => try writeReason(failure, &buf, a),
    }
    return vm.throwBuiltinException("Error", buf.items);
}

fn visibilityName(v: ClassDef.Visibility) []const u8 {
    return switch (v) {
        .public => "public",
        .protected => "protected",
        .private => "private",
    };
}
