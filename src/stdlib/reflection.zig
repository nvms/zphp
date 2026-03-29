const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    // ReflectionException
    var exc_def = ClassDef{ .name = "ReflectionException" };
    exc_def.parent = "Exception";
    try vm.classes.put(a, "ReflectionException", exc_def);

    // ReflectionClass
    var rc_def = ClassDef{ .name = "ReflectionClass" };
    try rc_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rc_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try rc_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rc_def.methods.put(a, "getConstructor", .{ .name = "getConstructor", .arity = 0 });
    try rc_def.methods.put(a, "isInstantiable", .{ .name = "isInstantiable", .arity = 0 });
    try rc_def.methods.put(a, "getParentClass", .{ .name = "getParentClass", .arity = 0 });
    try rc_def.methods.put(a, "implementsInterface", .{ .name = "implementsInterface", .arity = 1 });
    try rc_def.methods.put(a, "isSubclassOf", .{ .name = "isSubclassOf", .arity = 1 });
    try rc_def.methods.put(a, "newInstanceArgs", .{ .name = "newInstanceArgs", .arity = 1 });
    try rc_def.methods.put(a, "getMethods", .{ .name = "getMethods", .arity = 0 });
    try rc_def.methods.put(a, "getMethod", .{ .name = "getMethod", .arity = 1 });
    try rc_def.methods.put(a, "hasMethod", .{ .name = "hasMethod", .arity = 1 });
    try rc_def.methods.put(a, "isAbstract", .{ .name = "isAbstract", .arity = 0 });
    try rc_def.methods.put(a, "isInterface", .{ .name = "isInterface", .arity = 0 });
    try rc_def.methods.put(a, "getInterfaceNames", .{ .name = "getInterfaceNames", .arity = 0 });
    try rc_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try vm.classes.put(a, "ReflectionClass", rc_def);

    try vm.native_fns.put(a, "ReflectionClass::__construct", rcConstruct);
    try vm.native_fns.put(a, "ReflectionClass::getName", rcGetName);
    try vm.native_fns.put(a, "ReflectionClass::getConstructor", rcGetConstructor);
    try vm.native_fns.put(a, "ReflectionClass::isInstantiable", rcIsInstantiable);
    try vm.native_fns.put(a, "ReflectionClass::getParentClass", rcGetParentClass);
    try vm.native_fns.put(a, "ReflectionClass::implementsInterface", rcImplementsInterface);
    try vm.native_fns.put(a, "ReflectionClass::isSubclassOf", rcIsSubclassOf);
    try vm.native_fns.put(a, "ReflectionClass::newInstanceArgs", rcNewInstanceArgs);
    try vm.native_fns.put(a, "ReflectionClass::getMethods", rcGetMethods);
    try vm.native_fns.put(a, "ReflectionClass::getMethod", rcGetMethod);
    try vm.native_fns.put(a, "ReflectionClass::hasMethod", rcHasMethod);
    try vm.native_fns.put(a, "ReflectionClass::isAbstract", rcIsAbstract);
    try vm.native_fns.put(a, "ReflectionClass::isInterface", rcIsInterface);
    try vm.native_fns.put(a, "ReflectionClass::getInterfaceNames", rcGetInterfaceNames);
    try vm.native_fns.put(a, "ReflectionClass::getAttributes", rcGetAttributes);

    // ReflectionMethod
    var rm_def = ClassDef{ .name = "ReflectionMethod" };
    try rm_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rm_def.properties.append(a, .{ .name = "class", .default = .{ .string = "" } });
    try rm_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rm_def.methods.put(a, "getParameters", .{ .name = "getParameters", .arity = 0 });
    try rm_def.methods.put(a, "isPublic", .{ .name = "isPublic", .arity = 0 });
    try rm_def.methods.put(a, "isProtected", .{ .name = "isProtected", .arity = 0 });
    try rm_def.methods.put(a, "isPrivate", .{ .name = "isPrivate", .arity = 0 });
    try rm_def.methods.put(a, "isStatic", .{ .name = "isStatic", .arity = 0 });
    try rm_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rm_def.methods.put(a, "getReturnType", .{ .name = "getReturnType", .arity = 0 });
    try rm_def.methods.put(a, "isConstructor", .{ .name = "isConstructor", .arity = 0 });
    try rm_def.methods.put(a, "getNumberOfParameters", .{ .name = "getNumberOfParameters", .arity = 0 });
    try rm_def.methods.put(a, "getNumberOfRequiredParameters", .{ .name = "getNumberOfRequiredParameters", .arity = 0 });
    try rm_def.methods.put(a, "setAccessible", .{ .name = "setAccessible", .arity = 1 });
    try rm_def.methods.put(a, "invoke", .{ .name = "invoke", .arity = 1 });
    try rm_def.methods.put(a, "hasReturnType", .{ .name = "hasReturnType", .arity = 0 });
    try vm.classes.put(a, "ReflectionMethod", rm_def);

    try vm.native_fns.put(a, "ReflectionMethod::getName", rmGetName);
    try vm.native_fns.put(a, "ReflectionMethod::getParameters", rmGetParameters);
    try vm.native_fns.put(a, "ReflectionMethod::isPublic", rmIsPublic);
    try vm.native_fns.put(a, "ReflectionMethod::isProtected", rmIsProtected);
    try vm.native_fns.put(a, "ReflectionMethod::isPrivate", rmIsPrivate);
    try vm.native_fns.put(a, "ReflectionMethod::isStatic", rmIsStatic);
    try vm.native_fns.put(a, "ReflectionMethod::getDeclaringClass", rmGetDeclaringClass);
    try vm.native_fns.put(a, "ReflectionMethod::getReturnType", rmGetReturnType);
    try vm.native_fns.put(a, "ReflectionMethod::isConstructor", rmIsConstructor);
    try vm.native_fns.put(a, "ReflectionMethod::getNumberOfParameters", rmGetNumberOfParameters);
    try vm.native_fns.put(a, "ReflectionMethod::getNumberOfRequiredParameters", rmGetNumberOfRequiredParameters);
    try vm.native_fns.put(a, "ReflectionMethod::setAccessible", reflectionNoop);
    try vm.native_fns.put(a, "ReflectionMethod::invoke", rmInvoke);
    try vm.native_fns.put(a, "ReflectionMethod::hasReturnType", rmHasReturnType);

    // ReflectionParameter
    var rp_def = ClassDef{ .name = "ReflectionParameter" };
    try rp_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rp_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rp_def.methods.put(a, "getType", .{ .name = "getType", .arity = 0 });
    try rp_def.methods.put(a, "isDefaultValueAvailable", .{ .name = "isDefaultValueAvailable", .arity = 0 });
    try rp_def.methods.put(a, "getDefaultValue", .{ .name = "getDefaultValue", .arity = 0 });
    try rp_def.methods.put(a, "isOptional", .{ .name = "isOptional", .arity = 0 });
    try rp_def.methods.put(a, "getPosition", .{ .name = "getPosition", .arity = 0 });
    try rp_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rp_def.methods.put(a, "isPassedByReference", .{ .name = "isPassedByReference", .arity = 0 });
    try rp_def.methods.put(a, "hasType", .{ .name = "hasType", .arity = 0 });
    try rp_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rp_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rp_def.methods.put(a, "isVariadic", .{ .name = "isVariadic", .arity = 0 });
    try vm.classes.put(a, "ReflectionParameter", rp_def);

    try vm.native_fns.put(a, "ReflectionParameter::getName", rpGetName);
    try vm.native_fns.put(a, "ReflectionParameter::getType", rpGetType);
    try vm.native_fns.put(a, "ReflectionParameter::isDefaultValueAvailable", rpIsDefaultValueAvailable);
    try vm.native_fns.put(a, "ReflectionParameter::getDefaultValue", rpGetDefaultValue);
    try vm.native_fns.put(a, "ReflectionParameter::isOptional", rpIsOptional);
    try vm.native_fns.put(a, "ReflectionParameter::getPosition", rpGetPosition);
    try vm.native_fns.put(a, "ReflectionParameter::allowsNull", rpAllowsNull);
    try vm.native_fns.put(a, "ReflectionParameter::isPassedByReference", rpIsPassedByReference);
    try vm.native_fns.put(a, "ReflectionParameter::hasType", rpHasType);
    try vm.native_fns.put(a, "ReflectionParameter::getAttributes", rpGetAttributes);
    try vm.native_fns.put(a, "ReflectionParameter::getDeclaringClass", rpGetDeclaringClass);
    try vm.native_fns.put(a, "ReflectionParameter::isVariadic", rpIsVariadic);

    // ReflectionNamedType
    var rnt_def = ClassDef{ .name = "ReflectionNamedType" };
    try rnt_def.properties.append(a, .{ .name = "type_name", .default = .{ .string = "" } });
    try rnt_def.properties.append(a, .{ .name = "nullable", .default = .{ .bool = false } });
    try rnt_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rnt_def.methods.put(a, "isBuiltin", .{ .name = "isBuiltin", .arity = 0 });
    try rnt_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rnt_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionNamedType", rnt_def);

    try vm.native_fns.put(a, "ReflectionNamedType::getName", rntGetName);
    try vm.native_fns.put(a, "ReflectionNamedType::isBuiltin", rntIsBuiltin);
    try vm.native_fns.put(a, "ReflectionNamedType::allowsNull", rntAllowsNull);
    try vm.native_fns.put(a, "ReflectionNamedType::__toString", rntGetName);

    // ReflectionFunction
    var rf_def = ClassDef{ .name = "ReflectionFunction" };
    try rf_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rf_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try rf_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rf_def.methods.put(a, "getParameters", .{ .name = "getParameters", .arity = 0 });
    try rf_def.methods.put(a, "getReturnType", .{ .name = "getReturnType", .arity = 0 });
    try rf_def.methods.put(a, "getNumberOfParameters", .{ .name = "getNumberOfParameters", .arity = 0 });
    try rf_def.methods.put(a, "getNumberOfRequiredParameters", .{ .name = "getNumberOfRequiredParameters", .arity = 0 });
    try rf_def.methods.put(a, "isAnonymous", .{ .name = "isAnonymous", .arity = 0 });
    try rf_def.methods.put(a, "getClosureScopeClass", .{ .name = "getClosureScopeClass", .arity = 0 });
    try rf_def.methods.put(a, "hasReturnType", .{ .name = "hasReturnType", .arity = 0 });
    try vm.classes.put(a, "ReflectionFunction", rf_def);

    try vm.native_fns.put(a, "ReflectionFunction::__construct", rfConstruct);
    try vm.native_fns.put(a, "ReflectionFunction::getName", rfGetName);
    try vm.native_fns.put(a, "ReflectionFunction::getParameters", rfGetParameters);
    try vm.native_fns.put(a, "ReflectionFunction::getReturnType", rfGetReturnType);
    try vm.native_fns.put(a, "ReflectionFunction::getNumberOfParameters", rfGetNumberOfParameters);
    try vm.native_fns.put(a, "ReflectionFunction::getNumberOfRequiredParameters", rfGetNumberOfRequiredParameters);
    try vm.native_fns.put(a, "ReflectionFunction::isAnonymous", rfIsAnonymous);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureScopeClass", rfGetClosureScopeClass);
    try vm.native_fns.put(a, "ReflectionFunction::hasReturnType", rfHasReturnType);

    // ReflectionProperty
    var rprop_def = ClassDef{ .name = "ReflectionProperty" };
    try rprop_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rprop_def.properties.append(a, .{ .name = "class", .default = .{ .string = "" } });
    try rprop_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try rprop_def.methods.put(a, "setAccessible", .{ .name = "setAccessible", .arity = 1 });
    try rprop_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 1 });
    try rprop_def.methods.put(a, "setValue", .{ .name = "setValue", .arity = 2 });
    try vm.classes.put(a, "ReflectionProperty", rprop_def);

    try vm.native_fns.put(a, "ReflectionProperty::__construct", rpConstruct);
    try vm.native_fns.put(a, "ReflectionProperty::setAccessible", reflectionNoop);
    try vm.native_fns.put(a, "ReflectionProperty::getValue", rpGetValue);
    try vm.native_fns.put(a, "ReflectionProperty::setValue", rpSetValue);

    // ReflectionAttribute
    var ra_def = ClassDef{ .name = "ReflectionAttribute" };
    try ra_def.static_props.put(a, "IS_INSTANCEOF", .{ .int = 2 });
    try vm.classes.put(a, "ReflectionAttribute", ra_def);

    // Closure class (static methods only - instance methods handled in VM dispatch)
    var closure_def = ClassDef{ .name = "Closure" };
    try closure_def.methods.put(a, "bind", .{ .name = "bind", .arity = 2, .is_static = true });
    try closure_def.methods.put(a, "fromCallable", .{ .name = "fromCallable", .arity = 1, .is_static = true });
    try vm.classes.put(a, "Closure", closure_def);

    try vm.native_fns.put(a, "Closure::bind", closureBind);
    try vm.native_fns.put(a, "Closure::fromCallable", closureFromCallable);
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn throwReflection(ctx: *NativeContext, msg: []const u8) RuntimeError {
    _ = ctx.vm.throwBuiltinException("ReflectionException", msg) catch {};
    return error.RuntimeError;
}

fn isBuiltinType(name: []const u8) bool {
    const builtins = [_][]const u8{
        "int", "string", "bool", "float", "array", "callable",
        "null", "void", "never", "mixed", "object", "iterable", "false", "true",
    };
    for (builtins) |b| {
        if (std.mem.eql(u8, name, b)) return true;
    }
    return false;
}

fn resolveClassName(vm: *VM, name: []const u8) !?*const ClassDef {
    if (vm.classes.getPtr(name)) |cls| return cls;
    try vm.tryAutoload(name);
    return vm.classes.getPtr(name);
}

fn createNamedTypeObj(ctx: *NativeContext, type_name: []const u8, nullable: bool) !*PhpObject {
    const obj = try ctx.createObject("ReflectionNamedType");
    // strip leading ? for nullable types
    var clean_name = type_name;
    var is_nullable = nullable;
    if (type_name.len > 0 and type_name[0] == '?') {
        clean_name = type_name[1..];
        is_nullable = true;
    }
    try obj.set(ctx.allocator, "type_name", .{ .string = clean_name });
    try obj.set(ctx.allocator, "nullable", .{ .bool = is_nullable });
    return obj;
}

fn buildMethodObj(ctx: *NativeContext, class_name: []const u8, method_name: []const u8, info: ClassDef.MethodInfo, declaring_class: []const u8) !*PhpObject {
    const obj = try ctx.createObject("ReflectionMethod");
    try obj.set(ctx.allocator, "name", .{ .string = method_name });
    try obj.set(ctx.allocator, "class", .{ .string = class_name });
    try obj.set(ctx.allocator, "_declaring_class", .{ .string = declaring_class });
    try obj.set(ctx.allocator, "_is_static", .{ .bool = info.is_static });
    try obj.set(ctx.allocator, "_visibility", .{ .int = @intFromEnum(info.visibility) });

    // look up ObjFunction for parameter info
    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring_class, method_name }) catch return obj;
    if (ctx.vm.functions.get(key)) |func| {
        try obj.set(ctx.allocator, "_arity", .{ .int = func.arity });
        try obj.set(ctx.allocator, "_required_params", .{ .int = func.required_params });
    } else {
        try obj.set(ctx.allocator, "_arity", .{ .int = info.arity });
        try obj.set(ctx.allocator, "_required_params", .{ .int = info.arity });
    }
    return obj;
}

// find which class in the hierarchy actually declares a method
fn findDeclaringClass(vm: *VM, class_name: []const u8, method_name: []const u8) []const u8 {
    var current: []const u8 = class_name;
    var declaring: []const u8 = class_name;
    var buf: [256]u8 = undefined;
    while (true) {
        const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ current, method_name }) catch break;
        if (vm.functions.get(key) != null or vm.native_fns.get(key) != null) {
            declaring = current;
        }
        const cls = vm.classes.get(current) orelse break;
        current = cls.parent orelse break;
    }
    return declaring;
}

// --- ReflectionClass ---

fn rcConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::__construct() expects a class name");
    const class_name = args[0].string;
    const this = getThis(ctx) orelse return .null;

    _ = resolveClassName(ctx.vm, class_name) catch return throwReflection(ctx, "Class does not exist");
    if (ctx.vm.classes.get(class_name) == null and ctx.vm.interfaces.get(class_name) == null)
        return throwReflection(ctx, "Class does not exist");

    try this.set(ctx.allocator, "name", .{ .string = class_name });
    // track whether this is an interface
    try this.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(class_name) });
    return .null;
}

fn rcGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("name");
}

fn rcGetConstructor(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    if (!ctx.vm.hasMethod(class_name, "__construct")) return .null;

    const declaring = findDeclaringClass(ctx.vm, class_name, "__construct");
    const cls = ctx.vm.classes.get(declaring) orelse return .null;
    const info = cls.methods.get("__construct") orelse ClassDef.MethodInfo{ .name = "__construct", .arity = 0 };
    const obj = try buildMethodObj(ctx, class_name, "__construct", info, declaring);
    return .{ .object = obj };
}

fn rcIsInstantiable(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const is_iface = this.get("_is_interface");
    if (is_iface == .bool and is_iface.bool) return .{ .bool = false };
    return .{ .bool = true };
}

fn rcGetParentClass(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .bool = false };
    const parent_name = cls.parent orelse return .{ .bool = false };

    const parent_obj = try ctx.createObject("ReflectionClass");
    try parent_obj.set(ctx.allocator, "name", .{ .string = parent_name });
    try parent_obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(parent_name) });
    return .{ .object = parent_obj };
}

fn rcImplementsInterface(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const iface_name = args[0].string;
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        for (cls.interfaces.items) |iface| {
            if (std.mem.eql(u8, iface, iface_name)) return .{ .bool = true };
        }
        current = cls.parent;
    }
    return .{ .bool = false };
}

fn rcIsSubclassOf(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const parent_name = args[0].string;
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        current = cls.parent;
        if (current) |p| {
            if (std.mem.eql(u8, p, parent_name)) return .{ .bool = true };
        }
    }
    return .{ .bool = false };
}

fn rcNewInstanceArgs(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const arr = if (args.len >= 1 and args[0] == .array) args[0].array else return .null;

    var ctor_args: [16]Value = undefined;
    const count = @min(arr.entries.items.len, 16);
    for (0..count) |i| {
        ctor_args[i] = arr.entries.items[i].value;
    }

    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = class_name };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);

    if (ctx.vm.classes.get(class_name)) |cls| {
        for (cls.properties.items) |prop| {
            try obj.set(ctx.vm.allocator, prop.name, prop.default);
        }
    }

    if (ctx.vm.hasMethod(class_name, "__construct")) {
        _ = try ctx.callMethod(obj, "__construct", ctor_args[0..count]);
    }
    return .{ .object = obj };
}

fn rcGetMethods(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        var it = cls.methods.iterator();
        while (it.next()) |entry| {
            const method_name = entry.key_ptr.*;
            if (!seen.contains(method_name)) {
                try seen.put(ctx.allocator, method_name, {});
                const declaring = findDeclaringClass(ctx.vm, class_name, method_name);
                const obj = try buildMethodObj(ctx, class_name, method_name, entry.value_ptr.*, declaring);
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        }
        current = cls.parent;
    }
    return .{ .array = arr };
}

fn rcGetMethod(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::getMethod() expects a method name");
    const method_name = args[0].string;
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    if (!ctx.vm.hasMethod(class_name, method_name)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Method {s}::{s}() does not exist", .{ class_name, method_name }) catch return error.OutOfMemory;
        return throwReflection(ctx, msg);
    }

    const declaring = findDeclaringClass(ctx.vm, class_name, method_name);
    const cls = ctx.vm.classes.get(declaring) orelse return .null;
    const info = cls.methods.get(method_name) orelse ClassDef.MethodInfo{ .name = method_name, .arity = 0 };
    const obj = try buildMethodObj(ctx, class_name, method_name, info, declaring);
    return .{ .object = obj };
}

fn rcHasMethod(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    return .{ .bool = ctx.vm.hasMethod(class_name, args[0].string) };
}

fn rcIsAbstract(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const is_iface = this.get("_is_interface");
    if (is_iface == .bool and is_iface.bool) return .{ .bool = true };
    return .{ .bool = false };
}

fn rcIsInterface(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const is_iface = this.get("_is_interface");
    return .{ .bool = is_iface == .bool and is_iface.bool };
}

fn rcGetInterfaceNames(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const cls = ctx.vm.classes.get(class_name) orelse return .null;

    const arr = try ctx.createArray();
    for (cls.interfaces.items) |iface| {
        try arr.append(ctx.allocator, .{ .string = iface });
    }
    return .{ .array = arr };
}

fn rcGetAttributes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .array = try ctx.createArray() };
}

// --- ReflectionMethod ---

fn rmGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("name");
}

fn rmGetParameters(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const method_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .null;

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return .null;
    const func = ctx.vm.functions.get(key) orelse return .{ .array = try ctx.createArray() };

    return buildParamArray(ctx, func, key);
}

fn rmIsPublic(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const vis = this.get("_visibility");
    return .{ .bool = vis == .int and vis.int == 0 };
}

fn rmIsProtected(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const vis = this.get("_visibility");
    return .{ .bool = vis == .int and vis.int == 1 };
}

fn rmIsPrivate(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const vis = this.get("_visibility");
    return .{ .bool = vis == .int and vis.int == 2 };
}

fn rmIsStatic(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const is_static = this.get("_is_static");
    return .{ .bool = is_static == .bool and is_static.bool };
}

fn rmGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .null;

    const obj = try ctx.createObject("ReflectionClass");
    try obj.set(ctx.allocator, "name", .{ .string = declaring });
    try obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(declaring) });
    return .{ .object = obj };
}

fn rmGetReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const method_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .null;

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return .null;
    const type_info = vm_mod.getTypeInfo(key) orelse return .null;
    if (type_info.return_type.len == 0) return .null;

    const obj = try createNamedTypeObj(ctx, type_info.return_type, false);
    return .{ .object = obj };
}

fn rmHasReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const method_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .{ .bool = false };

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return .{ .bool = false };
    const type_info = vm_mod.getTypeInfo(key) orelse return .{ .bool = false };
    return .{ .bool = type_info.return_type.len > 0 };
}

fn rmIsConstructor(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const name = this.get("name");
    return .{ .bool = name == .string and std.mem.eql(u8, name.string, "__construct") };
}

fn rmGetNumberOfParameters(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .int = 0 };
    const arity = this.get("_arity");
    return if (arity == .int) arity else .{ .int = 0 };
}

fn rmGetNumberOfRequiredParameters(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .int = 0 };
    const req = this.get("_required_params");
    return if (req == .int) req else .{ .int = 0 };
}

// --- ReflectionParameter ---

fn rpGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("name");
}

fn rpGetType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const type_val = this.get("_type_name");
    if (type_val != .string or type_val.string.len == 0) return .null;

    const nullable = this.get("_nullable");
    const is_nullable = nullable == .bool and nullable.bool;
    const obj = try createNamedTypeObj(ctx, type_val.string, is_nullable);
    return .{ .object = obj };
}

fn rpIsDefaultValueAvailable(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const has_default = this.get("_has_default");
    return .{ .bool = has_default == .bool and has_default.bool };
}

fn rpGetDefaultValue(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const has_default = this.get("_has_default");
    if (has_default != .bool or !has_default.bool) return throwReflection(ctx, "Internal error: no default value available");
    return this.get("_default_value");
}

fn rpIsOptional(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const has_default = this.get("_has_default");
    return .{ .bool = has_default == .bool and has_default.bool };
}

fn rpGetPosition(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .int = 0 };
    return this.get("_position");
}

fn rpAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = true };
    // no type hint means allows null
    const type_val = this.get("_type_name");
    if (type_val != .string or type_val.string.len == 0) return .{ .bool = true };
    const nullable = this.get("_nullable");
    return .{ .bool = nullable == .bool and nullable.bool };
}

fn rpIsPassedByReference(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const by_ref = this.get("_by_reference");
    return .{ .bool = by_ref == .bool and by_ref.bool };
}

fn rpHasType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const type_val = this.get("_type_name");
    return .{ .bool = type_val == .string and type_val.string.len > 0 };
}

fn rpGetAttributes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .array = try ctx.createArray() };
}

fn rpGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const declaring = this.get("_declaring_class");
    if (declaring != .string or declaring.string.len == 0) return .null;

    const obj = try ctx.createObject("ReflectionClass");
    try obj.set(ctx.allocator, "name", declaring);
    try obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(declaring.string) });
    return .{ .object = obj };
}

fn rpIsVariadic(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const v = this.get("_is_variadic");
    return .{ .bool = v == .bool and v.bool };
}

// --- ReflectionNamedType ---

fn rntGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("type_name");
}

fn rntIsBuiltin(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const name = this.get("type_name");
    if (name != .string) return .{ .bool = false };
    return .{ .bool = isBuiltinType(name.string) };
}

fn rntAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const nullable = this.get("nullable");
    return .{ .bool = nullable == .bool and nullable.bool };
}

// --- ReflectionFunction ---

fn rfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return throwReflection(ctx, "ReflectionFunction::__construct() expects a function name");
    const this = getThis(ctx) orelse return .null;

    if (args[0] == .string) {
        const func_name = args[0].string;
        if (ctx.vm.functions.get(func_name) == null and ctx.vm.native_fns.get(func_name) == null)
            return throwReflection(ctx, "Function does not exist");
        try this.set(ctx.allocator, "name", .{ .string = func_name });
    } else if (args[0] == .array) {
        // array callable [$obj, 'method'] - store as method reference
        const arr = args[0].array;
        if (arr.entries.items.len == 2 and arr.entries.items[1].value == .string) {
            const method = arr.entries.items[1].value.string;
            const target = arr.entries.items[0].value;
            const class_name = if (target == .object) target.object.class_name else if (target == .string) target.string else "";
            const full = std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ class_name, method }) catch return .null;
            try ctx.strings.append(ctx.allocator, full);
            try this.set(ctx.allocator, "name", .{ .string = full });
            try this.set(ctx.allocator, "__is_method_ref", .{ .bool = true });
            if (target == .object) {
                try this.set(ctx.allocator, "__scope_class", .{ .string = class_name });
            }
        } else {
            return throwReflection(ctx, "ReflectionFunction::__construct() expects a function name");
        }
    } else {
        return throwReflection(ctx, "ReflectionFunction::__construct() expects a function name");
    }
    return .null;
}

fn rfGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("name");
}

fn rfGetParameters(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const func_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const func = ctx.vm.functions.get(func_name) orelse return .{ .array = try ctx.createArray() };
    return buildParamArray(ctx, func, func_name);
}

fn rfGetReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const func_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const type_info = vm_mod.getTypeInfo(func_name) orelse return .null;
    if (type_info.return_type.len == 0) return .null;

    const obj = try createNamedTypeObj(ctx, type_info.return_type, false);
    return .{ .object = obj };
}

fn rfHasReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const func_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };

    const type_info = vm_mod.getTypeInfo(func_name) orelse return .{ .bool = false };
    return .{ .bool = type_info.return_type.len > 0 };
}

fn rfGetNumberOfParameters(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .int = 0 };
    const func_name = if (this.get("name") == .string) this.get("name").string else return .{ .int = 0 };
    const func = ctx.vm.functions.get(func_name) orelse return .{ .int = 0 };
    return .{ .int = func.arity };
}

fn rfGetNumberOfRequiredParameters(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .int = 0 };
    const func_name = if (this.get("name") == .string) this.get("name").string else return .{ .int = 0 };
    const func = ctx.vm.functions.get(func_name) orelse return .{ .int = 0 };
    return .{ .int = func.required_params };
}

fn rfIsAnonymous(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    return .{ .bool = std.mem.startsWith(u8, name, "__closure_") };
}

fn rfGetClosureScopeClass(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const name = if (this.get("name") == .string) this.get("name").string else return .null;
    if (this.get("__scope_class") == .string) {
        const scope_name = this.get("__scope_class").string;
        const obj = try ctx.createObject("ReflectionClass");
        try obj.set(ctx.allocator, "name", .{ .string = scope_name });
        return .{ .object = obj };
    }
    _ = name;
    return .null;
}

// --- shared helpers ---

fn buildParamArray(ctx: *NativeContext, func: *const ObjFunction, type_key: []const u8) RuntimeError!Value {
    const arr = try ctx.createArray();
    const effective_key = if (std.mem.startsWith(u8, type_key, "__closure_")) blk: {
        const after_prefix = type_key["__closure_".len..];
        if (std.mem.lastIndexOf(u8, after_prefix, "_")) |last_us| {
            break :blk type_key[0 .. "__closure_".len + last_us];
        }
        break :blk type_key;
    } else type_key;
    const type_info = vm_mod.getTypeInfo(effective_key) orelse vm_mod.getTypeInfo(type_key);

    for (func.params, 0..) |param_name, i| {
        const obj = try ctx.createObject("ReflectionParameter");

        // strip $ prefix
        const clean_name = if (param_name.len > 0 and param_name[0] == '$') param_name[1..] else param_name;
        try obj.set(ctx.allocator, "name", .{ .string = clean_name });
        try obj.set(ctx.allocator, "_position", .{ .int = @intCast(i) });

        // type info
        if (type_info) |ti| {
            if (i < ti.param_types.len and ti.param_types[i].len > 0) {
                const raw_type = ti.param_types[i];
                if (raw_type[0] == '?') {
                    try obj.set(ctx.allocator, "_type_name", .{ .string = raw_type[1..] });
                    try obj.set(ctx.allocator, "_nullable", .{ .bool = true });
                } else {
                    try obj.set(ctx.allocator, "_type_name", .{ .string = raw_type });
                    try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
                }
            } else {
                try obj.set(ctx.allocator, "_type_name", .{ .string = "" });
                try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
            }
        } else {
            try obj.set(ctx.allocator, "_type_name", .{ .string = "" });
            try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
        }

        // default values - defaults array has one entry per param, non-default params have .null
        const has_default = i >= func.required_params;
        try obj.set(ctx.allocator, "_has_default", .{ .bool = has_default });
        if (has_default and i < func.defaults.len) {
            const raw = func.defaults[i];
            try obj.set(ctx.allocator, "_default_value", try ctx.vm.resolveDefault(raw));
        }

        // by-reference
        const by_ref = if (i < func.ref_params.len) func.ref_params[i] else false;
        try obj.set(ctx.allocator, "_by_reference", .{ .bool = by_ref });

        // variadic
        const is_variadic = func.is_variadic and i == func.arity - 1;
        try obj.set(ctx.allocator, "_is_variadic", .{ .bool = is_variadic });

        // declaring class
        if (std.mem.indexOf(u8, type_key, "::")) |sep| {
            try obj.set(ctx.allocator, "_declaring_class", .{ .string = type_key[0..sep] });
        }

        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return .{ .array = arr };
}

// --- Closure ---

fn closureBind(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .null;
    const closure = args[0];
    if (closure != .string or !std.mem.startsWith(u8, closure.string, "__closure_")) return .null;
    const new_this = if (args.len >= 2) args[1] else Value.null;
    const scope = resolveScope(args);
    return ctx.vm.cloneClosureWithThis(closure.string, new_this, scope);
}

fn resolveScope(args: []const Value) VM.ClosureScope {
    if (args.len >= 3) {
        const scope_arg = args[2];
        if (scope_arg == .null) return .clear;
        if (scope_arg == .string) {
            if (std.mem.eql(u8, scope_arg.string, "static")) return .preserve;
            return .{ .set = scope_arg.string };
        }
        if (scope_arg == .object) return .{ .set = scope_arg.object.class_name };
        return .clear;
    }
    return .preserve;
}

fn closureFromCallable(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return .null;
    const callable = args[0];
    // if already a closure, return as-is
    if (callable == .string and std.mem.startsWith(u8, callable.string, "__closure_")) return callable;
    // if it's a string function name, wrap it (just return the name - it's callable)
    if (callable == .string) {
        if (ctx.vm.functions.contains(callable.string) or ctx.vm.native_fns.contains(callable.string))
            return callable;
    }
    // array callable [obj, method] or [class, method]
    if (callable == .array) {
        const entries = callable.array.entries.items;
        if (entries.len == 2 and entries[1].value == .string) {
            if (entries[0].value == .string) {
                // static method - return "Class::method" string
                const full = std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ entries[0].value.string, entries[1].value.string }) catch return .null;
                try ctx.strings.append(ctx.allocator, full);
                return .{ .string = full };
            }
        }
    }
    return callable;
}

fn reflectionNoop(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

// --- ReflectionProperty ---

fn rpConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2) return throwReflection(ctx, "ReflectionProperty::__construct() expects class and property name");
    const this = getThis(ctx) orelse return .null;

    const class_name = if (args[0] == .string) args[0].string else if (args[0] == .object) args[0].object.class_name else return throwReflection(ctx, "ReflectionProperty::__construct() expects a class name");
    const prop_name = if (args[1] == .string) args[1].string else return throwReflection(ctx, "ReflectionProperty::__construct() expects a property name");

    try this.set(ctx.allocator, "name", .{ .string = prop_name });
    try this.set(ctx.allocator, "class", .{ .string = class_name });
    return .null;
}

fn rpGetValue(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const prop_name = if (this.get("name") == .string) this.get("name").string else return .null;
    if (args.len > 0 and args[0] == .object) {
        return args[0].object.get(prop_name);
    }
    return .null;
}

fn rpSetValue(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const prop_name = if (this.get("name") == .string) this.get("name").string else return .null;
    if (args.len >= 2 and args[0] == .object) {
        try args[0].object.set(ctx.allocator, prop_name, args[1]);
    }
    return .null;
}

// --- ReflectionMethod::invoke ---

fn rmInvoke(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const method_name = if (this.get("name") == .string) this.get("name").string else return .null;
    if (args.len > 0 and args[0] == .object) {
        return ctx.invokeCallable(.{ .string = method_name }, args[1..]) catch .null;
    }
    return .null;
}
