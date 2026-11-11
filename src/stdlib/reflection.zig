const std = @import("std");
const class_names = @import("../runtime/class_names.zig");
const php_types = @import("../pipeline/php_types.zig");
const object_properties = @import("../runtime/object_properties.zig");
const deprecations = @import("deprecations_generated.zig");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const bytecode = @import("../pipeline/bytecode.zig");
const php_version = @import("../php_version.zig");
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const native_params = @import("native_params.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const AttributeDef = vm_mod.AttributeDef;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;
const extensions = @import("extensions_generated.zig");

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

fn retainReturned(value: Value) Value {
    if (value == .string) value.string.retain();
    return value;
}

// the function and parameter a default belongs to, resolved when asked for.
// the compiled default is owned by the compile result, so it is never stored
// in a property; `_default_value` only says whether the default is null, which
// the implicitly nullable type check reads
fn setLazyDefault(ctx: *NativeContext, obj: *PhpObject, func: *const ObjFunction, index: usize) !void {
    try obj.set(ctx.allocator, "__default_value", if (func.defaults[index] == .null) .null else .{ .bool = false });
    try obj.set(ctx.allocator, "__default_func", .{ .int = @intCast(@intFromPtr(func)) });
    try obj.set(ctx.allocator, "__default_index", .{ .int = @intCast(index) });
}

pub fn register(vm: *VM, a: Allocator) !void {
    // Unit enum cases are request-lifetime objects, just like RoundingMode.
    var hook_type = ClassDef{ .name = "PropertyHookType", .is_enum = true, .is_final = true };
    for ([_][]const u8{ "Get", "Set" }) |name| {
        const obj = try a.create(PhpObject);
        obj.* = .{ .class_name = "PropertyHookType" };
        try vm.objects.append(a, obj);
        try obj.set(a, "name", .{ .string = Value.String.borrowed(name) });
        VM.objRetain(obj);
        try hook_type.constants.put(a, name, .{ .object = obj });
        try hook_type.constant_order.append(a, name);
        try hook_type.case_order.append(a, name);
    }
    try hook_type.interfaces.append(a, "UnitEnum");
    try hook_type.addMethod(a, .{ .name = "cases", .arity = 0, .is_static = true });
    try vm.classes.put(a, "PropertyHookType", hook_type);
    try vm.native_fns.put(a, "PropertyHookType::cases", @import("enums.zig").enumCases);

    // Reflector marker interface - all Reflection* implement it
    var reflector_iface = @import("../runtime/vm.zig").InterfaceDef{ .name = "Reflector" };
    try reflector_iface.methods.append(a, "__toString");
    reflector_iface.parent = "Stringable";
    try reflector_iface.parents.append(a, "Stringable");
    try vm.interfaces.put(a, "Reflector", reflector_iface);

    // ReflectionType abstract base class. ReflectionNamedType / Union / Intersection
    // all extend it. registering as a concrete class is fine since user code only
    // checks instanceof / get_parent_class
    var rt_def = ClassDef{ .name = "ReflectionType" };
    try rt_def.interfaces.append(a, "Stringable");
    rt_def.is_abstract = true;
    try rt_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rt_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionType", rt_def);

    var attr_def = ClassDef{ .name = "Attribute" };
    try attr_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try attr_def.constants.put(a, "TARGET_CLASS", .{ .int = 1 });
    try attr_def.constants.put(a, "TARGET_FUNCTION", .{ .int = 2 });
    try attr_def.constants.put(a, "TARGET_METHOD", .{ .int = 4 });
    try attr_def.constants.put(a, "TARGET_PROPERTY", .{ .int = 8 });
    try attr_def.constants.put(a, "TARGET_CLASS_CONSTANT", .{ .int = 16 });
    try attr_def.constants.put(a, "TARGET_PARAMETER", .{ .int = 32 });
    try attr_def.constants.put(a, "TARGET_CONSTANT", .{ .int = 64 });
    try attr_def.constants.put(a, "TARGET_ALL", .{ .int = 127 });
    try attr_def.constants.put(a, "IS_REPEATABLE", .{ .int = 128 });
    attr_def.is_final = true;
    try attr_def.attributes.append(a, .{ .name = "Attribute", .args = try attributeTargets(a, 1) });
    try vm.classes.put(a, "Attribute", attr_def);
    try vm.native_fns.put(a, "Attribute::__construct", attributeConstruct);

    // PHP 8.3 #[Override] marker. enforcement happens elsewhere - here we
    // register the class so attribute reflection and class_exists pick it up
    var override_def = ClassDef{ .name = "Override", .is_final = true };
    try override_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try override_def.attributes.append(a, .{ .name = "Attribute", .args = try attributeTargets(a, 12) });
    try vm.classes.put(a, "Override", override_def);

    // PHP 8.2 #[SensitiveParameter] - marks parameters whose values should be
    // redacted from stack traces. Stub the class for attribute usage
    var sp_def = ClassDef{ .name = "SensitiveParameter", .is_final = true };
    try sp_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try sp_def.attributes.append(a, .{ .name = "Attribute", .args = try attributeTargets(a, 32) });
    try vm.classes.put(a, "SensitiveParameter", sp_def);

    // the other attributes php itself declares, with the targets their
    // #[Attribute] allows (ReflectionAttribute::newInstance enforces them)
    inline for (.{ .{ "AllowDynamicProperties", 1, true }, .{ "ReturnTypeWillChange", 4, true }, .{ "DelayedTargetValidation", 127, false } }) |spec| {
        var def = ClassDef{ .name = spec[0], .is_final = true };
        if (spec[2]) try def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
        try def.attributes.append(a, .{ .name = "Attribute", .args = try attributeTargets(a, spec[1]) });
        try vm.classes.put(a, spec[0], def);
    }

    // php 8.5 #[NoDiscard]; the compiler and vm act on it, this is the class
    // reflection instantiates
    var nd_def = ClassDef{ .name = "NoDiscard", .is_final = true };
    try nd_def.properties.append(a, .{ .name = "message", .default = .null, .has_default = true, .is_readonly = true, .type_str = "?string" });
    try nd_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try nd_def.attributes.append(a, .{ .name = "Attribute", .args = try attributeTargets(a, 6) });
    try vm.classes.put(a, "NoDiscard", nd_def);
    try vm.native_fns.put(a, "NoDiscard::__construct", noDiscardConstruct);

    // PHP 8.4 #[Deprecated]: reflection reports it through isDeprecated(),
    // the compiler and vm raise its warnings
    var dep_def = ClassDef{ .name = "Deprecated", .is_final = true };
    try dep_def.properties.append(a, .{ .name = "message", .default = .null, .has_default = true, .is_readonly = true, .type_str = "?string" });
    try dep_def.properties.append(a, .{ .name = "since", .default = .null, .has_default = true, .is_readonly = true, .type_str = "?string" });
    try dep_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try dep_def.attributes.append(a, .{ .name = "Attribute", .args = try attributeTargets(a, 87) });
    try vm.classes.put(a, "Deprecated", dep_def);
    try vm.native_fns.put(a, "Deprecated::__construct", deprecatedConstruct);

    var rconst_def = ClassDef{ .name = "ReflectionConstant" };
    try rconst_def.interfaces.append(a, "Reflector");
    try rconst_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    inline for (.{ .{ "__construct", 1 }, .{ "getName", 0 }, .{ "getValue", 0 }, .{ "getShortName", 0 }, .{ "getNamespaceName", 0 }, .{ "isDeprecated", 0 }, .{ "getAttributes", 2 }, .{ "getFileName", 0 }, .{ "__toString", 0 }, .{ "getExtension", 0 }, .{ "getExtensionName", 0 } }) |m| {
        try rconst_def.methods.put(a, m[0], .{ .name = m[0], .arity = m[1] });
    }
    try vm.classes.put(a, "ReflectionConstant", rconst_def);
    try vm.native_fns.put(a, "ReflectionConstant::__construct", rconstConstruct);
    try vm.native_fns.put(a, "ReflectionConstant::getName", rconstGetName);
    try vm.native_fns.put(a, "ReflectionConstant::getValue", rconstGetValue);
    try vm.native_fns.put(a, "ReflectionConstant::getShortName", rconstGetShortName);
    try vm.native_fns.put(a, "ReflectionConstant::getNamespaceName", rconstGetNamespaceName);
    try vm.native_fns.put(a, "ReflectionConstant::isDeprecated", rconstIsDeprecated);
    try vm.native_fns.put(a, "ReflectionConstant::getAttributes", rconstGetAttributes);
    try vm.native_fns.put(a, "ReflectionConstant::getFileName", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionConstant::getExtension", rconstGetExtension);
    try vm.native_fns.put(a, "ReflectionConstant::getExtensionName", rconstGetExtensionName);
    try vm.native_fns.put(a, "ReflectionConstant::__toString", rconstToString);

    // SensitiveParameterValue (PHP 8.2) - returned by debug_backtrace for
    // redacted sensitive params. simple value wrapper
    var spv_def = ClassDef{ .name = "SensitiveParameterValue" };
    try spv_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try spv_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 0 });
    try vm.classes.put(a, "SensitiveParameterValue", spv_def);

    var exc_def = ClassDef{ .name = "ReflectionException" };
    exc_def.parent = "Exception";
    try vm.classes.put(a, "ReflectionException", exc_def);

    var refl_def = ClassDef{ .name = "Reflection" };
    try refl_def.methods.put(a, "getModifierNames", .{ .name = "getModifierNames", .arity = 1, .is_static = true });
    try vm.classes.put(a, "Reflection", refl_def);
    try vm.native_fns.put(a, "Reflection::getModifierNames", reflectionGetModifierNames);

    var rc_def = ClassDef{ .name = "ReflectionClass" };
    try rc_def.constants.put(a, "IS_IMPLICIT_ABSTRACT", .{ .int = 16 });
    try rc_def.constants.put(a, "IS_EXPLICIT_ABSTRACT", .{ .int = 64 });
    try rc_def.constants.put(a, "IS_FINAL", .{ .int = 32 });
    try rc_def.constants.put(a, "IS_READONLY", .{ .int = 65536 });
    try rc_def.constants.put(a, "SKIP_DESTRUCTOR", .{ .int = 16 });
    try rc_def.interfaces.append(a, "Reflector");
    try rc_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try rc_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try rc_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rc_def.methods.put(a, "getConstructor", .{ .name = "getConstructor", .arity = 0 });
    try rc_def.methods.put(a, "isInstantiable", .{ .name = "isInstantiable", .arity = 0 });
    try rc_def.methods.put(a, "getParentClass", .{ .name = "getParentClass", .arity = 0 });
    try rc_def.methods.put(a, "implementsInterface", .{ .name = "implementsInterface", .arity = 1 });
    try rc_def.methods.put(a, "isSubclassOf", .{ .name = "isSubclassOf", .arity = 1 });
    try rc_def.methods.put(a, "isInstance", .{ .name = "isInstance", .arity = 1 });
    try rc_def.methods.put(a, "isFinal", .{ .name = "isFinal", .arity = 0 });
    try rc_def.methods.put(a, "isReadOnly", .{ .name = "isReadOnly", .arity = 0 });
    // PHP 8.2+ docs use 'isReadonly' (lowercase o) and most code calls it
    // that way. method lookup is case-sensitive in zphp so register both
    try rc_def.methods.put(a, "isReadonly", .{ .name = "isReadonly", .arity = 0 });
    try rc_def.methods.put(a, "getModifiers", .{ .name = "getModifiers", .arity = 0 });
    try rc_def.methods.put(a, "isCloneable", .{ .name = "isCloneable", .arity = 0 });
    inline for (.{ "getExtension", "getExtensionName", "isIterable", "isIterateable" }) |m| try rc_def.methods.put(a, m, .{ .name = m, .arity = 0 });
    try rc_def.methods.put(a, "newInstanceArgs", .{ .name = "newInstanceArgs", .arity = 1 });
    try rc_def.methods.put(a, "newInstance", .{ .name = "newInstance", .arity = 0 });
    try rc_def.methods.put(a, "getMethods", .{ .name = "getMethods", .arity = 1 });
    try rc_def.methods.put(a, "getMethod", .{ .name = "getMethod", .arity = 1 });
    try rc_def.methods.put(a, "hasMethod", .{ .name = "hasMethod", .arity = 1 });
    try rc_def.methods.put(a, "isAbstract", .{ .name = "isAbstract", .arity = 0 });
    try rc_def.methods.put(a, "isInterface", .{ .name = "isInterface", .arity = 0 });
    try rc_def.methods.put(a, "isAnonymous", .{ .name = "isAnonymous", .arity = 0 });
    try rc_def.methods.put(a, "getInterfaceNames", .{ .name = "getInterfaceNames", .arity = 0 });
    try rc_def.methods.put(a, "getInterfaces", .{ .name = "getInterfaces", .arity = 0 });
    try rc_def.methods.put(a, "getTraits", .{ .name = "getTraits", .arity = 0 });
    try rc_def.methods.put(a, "getTraitNames", .{ .name = "getTraitNames", .arity = 0 });
    try rc_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rc_def.methods.put(a, "getDocComment", .{ .name = "getDocComment", .arity = 0 });
    try rc_def.methods.put(a, "getProperties", .{ .name = "getProperties", .arity = 1 });
    try rc_def.methods.put(a, "getProperty", .{ .name = "getProperty", .arity = 1 });
    try rc_def.methods.put(a, "hasProperty", .{ .name = "hasProperty", .arity = 1 });
    try rc_def.methods.put(a, "newInstanceWithoutConstructor", .{ .name = "newInstanceWithoutConstructor", .arity = 0 });
    try rc_def.constants.put(a, "SKIP_INITIALIZATION_ON_SERIALIZE", .{ .int = 8 });
    try rc_def.methods.put(a, "newLazyGhost", .{ .name = "newLazyGhost", .arity = 1 });
    try rc_def.methods.put(a, "newLazyProxy", .{ .name = "newLazyProxy", .arity = 1 });
    try rc_def.methods.put(a, "initializeLazyObject", .{ .name = "initializeLazyObject", .arity = 1 });
    try rc_def.methods.put(a, "isUninitializedLazyObject", .{ .name = "isUninitializedLazyObject", .arity = 1 });
    try rc_def.methods.put(a, "markLazyObjectAsInitialized", .{ .name = "markLazyObjectAsInitialized", .arity = 1 });
    try rc_def.methods.put(a, "resetAsLazyGhost", .{ .name = "resetAsLazyGhost", .arity = 2 });
    try rc_def.methods.put(a, "resetAsLazyProxy", .{ .name = "resetAsLazyProxy", .arity = 2 });
    try rc_def.methods.put(a, "getLazyInitializer", .{ .name = "getLazyInitializer", .arity = 1 });
    try rc_def.methods.put(a, "getShortName", .{ .name = "getShortName", .arity = 0 });
    try rc_def.methods.put(a, "getNamespaceName", .{ .name = "getNamespaceName", .arity = 0 });
    try rc_def.methods.put(a, "inNamespace", .{ .name = "inNamespace", .arity = 0 });
    try rc_def.methods.put(a, "isTrait", .{ .name = "isTrait", .arity = 0 });
    try rc_def.methods.put(a, "getTraitNames", .{ .name = "getTraitNames", .arity = 0 });
    try rc_def.methods.put(a, "isEnum", .{ .name = "isEnum", .arity = 0 });
    try rc_def.methods.put(a, "getConstants", .{ .name = "getConstants", .arity = 0 });
    try rc_def.methods.put(a, "getReflectionConstants", .{ .name = "getReflectionConstants", .arity = 0 });
    try rc_def.methods.put(a, "getReflectionConstant", .{ .name = "getReflectionConstant", .arity = 1 });
    try rc_def.methods.put(a, "hasConstant", .{ .name = "hasConstant", .arity = 1 });
    try rc_def.methods.put(a, "getConstant", .{ .name = "getConstant", .arity = 1 });
    try rc_def.methods.put(a, "isInternal", .{ .name = "isInternal", .arity = 0 });
    try rc_def.methods.put(a, "isUserDefined", .{ .name = "isUserDefined", .arity = 0 });
    try rc_def.methods.put(a, "getFileName", .{ .name = "getFileName", .arity = 0 });
    try rc_def.methods.put(a, "getStartLine", .{ .name = "getStartLine", .arity = 0 });
    try rc_def.methods.put(a, "getEndLine", .{ .name = "getEndLine", .arity = 0 });
    try rc_def.methods.put(a, "getDefaultProperties", .{ .name = "getDefaultProperties", .arity = 0 });
    try rc_def.methods.put(a, "getStaticProperties", .{ .name = "getStaticProperties", .arity = 0 });
    try rc_def.methods.put(a, "getStaticPropertyValue", .{ .name = "getStaticPropertyValue", .arity = 2 });
    try rc_def.methods.put(a, "setStaticPropertyValue", .{ .name = "setStaticPropertyValue", .arity = 2 });
    try vm.classes.put(a, "ReflectionClass", rc_def);

    try vm.native_fns.put(a, "ReflectionClass::__construct", rcConstruct);
    try vm.native_fns.put(a, "ReflectionClass::getName", rcGetName);
    try vm.native_fns.put(a, "ReflectionClass::getConstructor", rcGetConstructor);
    try vm.native_fns.put(a, "ReflectionClass::isInstantiable", rcIsInstantiable);
    try vm.native_fns.put(a, "ReflectionClass::getParentClass", rcGetParentClass);
    try vm.native_fns.put(a, "ReflectionClass::implementsInterface", rcImplementsInterface);
    try vm.native_fns.put(a, "ReflectionClass::isSubclassOf", rcIsSubclassOf);
    try vm.native_fns.put(a, "ReflectionClass::isInstance", rcIsInstance);
    try vm.native_fns.put(a, "ReflectionClass::newInstanceArgs", rcNewInstanceArgs);
    try vm.native_fns.put(a, "ReflectionClass::newInstance", rcNewInstance);
    try vm.native_fns.put(a, "ReflectionClass::getMethods", rcGetMethods);
    try vm.native_fns.put(a, "ReflectionClass::getMethod", rcGetMethod);
    try vm.native_fns.put(a, "ReflectionClass::hasMethod", rcHasMethod);
    try vm.native_fns.put(a, "ReflectionClass::isAbstract", rcIsAbstract);
    try vm.native_fns.put(a, "ReflectionClass::isInterface", rcIsInterface);
    try vm.native_fns.put(a, "ReflectionClass::isAnonymous", rcIsAnonymous);
    try vm.native_fns.put(a, "ReflectionClass::getInterfaceNames", rcGetInterfaceNames);
    try vm.native_fns.put(a, "ReflectionClass::getInterfaces", rcGetInterfaces);
    try vm.native_fns.put(a, "ReflectionClass::getTraits", rcGetTraits);
    try vm.native_fns.put(a, "ReflectionClass::getTraitNames", rcGetTraitNames);
    try vm.native_fns.put(a, "ReflectionClass::getAttributes", rcGetAttributes);
    try vm.native_fns.put(a, "ReflectionClass::getDocComment", rcGetDocComment);
    try vm.native_fns.put(a, "ReflectionClass::getProperties", rcGetProperties);
    try vm.native_fns.put(a, "ReflectionClass::getProperty", rcGetProperty);
    try vm.native_fns.put(a, "ReflectionClass::hasProperty", rcHasProperty);
    try vm.native_fns.put(a, "ReflectionClass::newInstanceWithoutConstructor", rcNewInstanceWithoutConstructor);
    try vm.native_fns.put(a, "ReflectionClass::newLazyGhost", rcNewLazyGhost);
    try vm.native_fns.put(a, "ReflectionClass::newLazyProxy", rcNewLazyProxy);
    try vm.native_fns.put(a, "ReflectionClass::initializeLazyObject", rcInitializeLazyObject);
    try vm.native_fns.put(a, "ReflectionClass::isUninitializedLazyObject", rcIsUninitializedLazyObject);
    try vm.native_fns.put(a, "ReflectionClass::markLazyObjectAsInitialized", rcMarkLazyObjectAsInitialized);
    try vm.native_fns.put(a, "ReflectionClass::resetAsLazyGhost", rcResetAsLazyGhost);
    try vm.native_fns.put(a, "ReflectionClass::resetAsLazyProxy", rcResetAsLazyProxy);
    try vm.native_fns.put(a, "ReflectionClass::getLazyInitializer", rcGetLazyInitializer);
    try vm.native_fns.put(a, "ReflectionClass::getShortName", rcGetShortName);
    try vm.native_fns.put(a, "ReflectionClass::getNamespaceName", rcGetNamespaceName);
    try vm.native_fns.put(a, "ReflectionClass::inNamespace", rcInNamespace);
    try vm.native_fns.put(a, "ReflectionClass::isTrait", rcIsTrait);
    try vm.native_fns.put(a, "ReflectionClass::getTraitNames", rcGetTraitNames);
    try vm.native_fns.put(a, "ReflectionClass::isEnum", rcIsEnum);
    try vm.native_fns.put(a, "ReflectionClass::getConstants", rcGetConstants);
    try vm.native_fns.put(a, "ReflectionClass::getReflectionConstants", rcGetReflectionConstants);
    try vm.native_fns.put(a, "ReflectionClass::getReflectionConstant", rcGetReflectionConstant);
    try vm.native_fns.put(a, "ReflectionClass::hasConstant", rcHasConstant);
    try vm.native_fns.put(a, "ReflectionClass::getConstant", rcGetConstant);
    try vm.native_fns.put(a, "ReflectionClass::isInternal", rcIsInternal);
    try vm.native_fns.put(a, "ReflectionClass::isUserDefined", rcIsUserDefined);
    try vm.native_fns.put(a, "ReflectionClass::getFileName", rcGetFileName);
    try vm.native_fns.put(a, "ReflectionClass::getStartLine", rcGetStartLine);
    try vm.native_fns.put(a, "ReflectionClass::getEndLine", rcGetEndLine);
    try vm.native_fns.put(a, "ReflectionClass::getDefaultProperties", rcGetDefaultProperties);
    try vm.native_fns.put(a, "ReflectionClass::getStaticProperties", rcGetStaticProperties);
    try vm.native_fns.put(a, "ReflectionClass::getStaticPropertyValue", rcGetStaticPropertyValue);
    try vm.native_fns.put(a, "ReflectionClass::setStaticPropertyValue", rcSetStaticPropertyValue);
    try vm.native_fns.put(a, "ReflectionClass::isFinal", rcIsFinal);
    try vm.native_fns.put(a, "ReflectionClass::isReadOnly", rcIsReadOnly);
    try vm.native_fns.put(a, "ReflectionClass::isReadonly", rcIsReadOnly);
    try vm.native_fns.put(a, "ReflectionClass::getModifiers", rcGetModifiers);
    try vm.native_fns.put(a, "ReflectionClass::isCloneable", rcIsCloneable);
    try vm.native_fns.put(a, "ReflectionClass::getExtension", rcGetExtension);
    try vm.native_fns.put(a, "ReflectionClass::getExtensionName", rcGetExtensionName);
    try vm.native_fns.put(a, "ReflectionClass::isIterable", rcIsIterable);
    try vm.native_fns.put(a, "ReflectionClass::isIterateable", rcIsIterable);

    // ReflectionObject extends ReflectionClass. behavior is identical to
    // ReflectionClass(get_class($obj)) when constructed with an instance,
    // so register an empty subclass and let method dispatch fall through
    var ro_def = ClassDef{ .name = "ReflectionObject", .parent = "ReflectionClass" };
    try ro_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try vm.classes.put(a, "ReflectionObject", ro_def);

    var rfa_def = ClassDef{ .name = "ReflectionFunctionAbstract", .is_abstract = true };
    try rfa_def.interfaces.append(a, "Reflector");
    try vm.classes.put(a, "ReflectionFunctionAbstract", rfa_def);

    var rm_def = ClassDef{ .name = "ReflectionMethod", .parent = "ReflectionFunctionAbstract" };
    try rm_def.constants.put(a, "IS_STATIC", .{ .int = 16 });
    try rm_def.constants.put(a, "IS_PUBLIC", .{ .int = 1 });
    try rm_def.constants.put(a, "IS_PROTECTED", .{ .int = 2 });
    try rm_def.constants.put(a, "IS_PRIVATE", .{ .int = 4 });
    try rm_def.constants.put(a, "IS_ABSTRACT", .{ .int = 64 });
    try rm_def.constants.put(a, "IS_FINAL", .{ .int = 32 });
    try rm_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try rm_def.properties.append(a, .{ .name = "class", .default = .{ .string = Value.String.borrowed("") } });
    try rm_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try rm_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rm_def.methods.put(a, "getParameters", .{ .name = "getParameters", .arity = 0 });
    try rm_def.methods.put(a, "isPublic", .{ .name = "isPublic", .arity = 0 });
    try rm_def.methods.put(a, "isProtected", .{ .name = "isProtected", .arity = 0 });
    try rm_def.methods.put(a, "isPrivate", .{ .name = "isPrivate", .arity = 0 });
    try rm_def.methods.put(a, "isStatic", .{ .name = "isStatic", .arity = 0 });
    try rm_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rm_def.methods.put(a, "getReturnType", .{ .name = "getReturnType", .arity = 0 });
    try rm_def.methods.put(a, "isConstructor", .{ .name = "isConstructor", .arity = 0 });
    try rm_def.methods.put(a, "isDestructor", .{ .name = "isDestructor", .arity = 0 });
    try rm_def.methods.put(a, "getDocComment", .{ .name = "getDocComment", .arity = 0 });
    try rm_def.methods.put(a, "getNumberOfParameters", .{ .name = "getNumberOfParameters", .arity = 0 });
    try rm_def.methods.put(a, "getNumberOfRequiredParameters", .{ .name = "getNumberOfRequiredParameters", .arity = 0 });
    try rm_def.methods.put(a, "setAccessible", .{ .name = "setAccessible", .arity = 1 });
    try rm_def.methods.put(a, "invoke", .{ .name = "invoke", .arity = 1 });
    try rm_def.methods.put(a, "hasReturnType", .{ .name = "hasReturnType", .arity = 0 });
    try rm_def.methods.put(a, "hasTentativeReturnType", .{ .name = "hasTentativeReturnType", .arity = 0 });
    try rm_def.methods.put(a, "getTentativeReturnType", .{ .name = "getTentativeReturnType", .arity = 0 });
    try rm_def.methods.put(a, "invokeArgs", .{ .name = "invokeArgs", .arity = 2 });
    try rm_def.methods.put(a, "isAbstract", .{ .name = "isAbstract", .arity = 0 });
    try rm_def.methods.put(a, "isFinal", .{ .name = "isFinal", .arity = 0 });
    try rm_def.methods.put(a, "isVariadic", .{ .name = "isVariadic", .arity = 0 });
    try rm_def.methods.put(a, "isGenerator", .{ .name = "isGenerator", .arity = 0 });
    try rm_def.methods.put(a, "returnsReference", .{ .name = "returnsReference", .arity = 0 });
    try rm_def.methods.put(a, "getModifiers", .{ .name = "getModifiers", .arity = 0 });
    try rm_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rm_def.methods.put(a, "getClosure", .{ .name = "getClosure", .arity = 1 });
    try rm_def.methods.put(a, "getFileName", .{ .name = "getFileName", .arity = 0 });
    try rm_def.methods.put(a, "getStartLine", .{ .name = "getStartLine", .arity = 0 });
    try rm_def.methods.put(a, "getEndLine", .{ .name = "getEndLine", .arity = 0 });
    try rm_def.methods.put(a, "getNamespaceName", .{ .name = "getNamespaceName", .arity = 0 });
    try rm_def.methods.put(a, "getShortName", .{ .name = "getShortName", .arity = 0 });
    try rm_def.methods.put(a, "inNamespace", .{ .name = "inNamespace", .arity = 0 });
    try rm_def.methods.put(a, "isInternal", .{ .name = "isInternal", .arity = 0 });
    try rm_def.methods.put(a, "isUserDefined", .{ .name = "isUserDefined", .arity = 0 });
    try rm_def.methods.put(a, "isDeprecated", .{ .name = "isDeprecated", .arity = 0 });
    try rm_def.methods.put(a, "getStaticVariables", .{ .name = "getStaticVariables", .arity = 0 });
    try rm_def.methods.put(a, "getExtension", .{ .name = "getExtension", .arity = 0 });
    try rm_def.methods.put(a, "getPrototype", .{ .name = "getPrototype", .arity = 0 });
    try rm_def.methods.put(a, "hasPrototype", .{ .name = "hasPrototype", .arity = 0 });
    try rm_def.methods.put(a, "getExtensionName", .{ .name = "getExtensionName", .arity = 0 });
    try rm_def.methods.put(a, "createFromMethodName", .{ .name = "createFromMethodName", .arity = 1, .is_static = true });
    try vm.classes.put(a, "ReflectionMethod", rm_def);

    try vm.native_fns.put(a, "ReflectionMethod::__construct", rmConstruct);
    try vm.native_fns.put(a, "ReflectionMethod::createFromMethodName", rmCreateFromMethodName);
    try vm.native_fns.put(a, "ReflectionMethod::getName", rmGetName);
    try vm.native_fns.put(a, "ReflectionMethod::getParameters", rmGetParameters);
    try vm.native_fns.put(a, "ReflectionMethod::isPublic", rmIsPublic);
    try vm.native_fns.put(a, "ReflectionMethod::isProtected", rmIsProtected);
    try vm.native_fns.put(a, "ReflectionMethod::isPrivate", rmIsPrivate);
    try vm.native_fns.put(a, "ReflectionMethod::isStatic", rmIsStatic);
    try vm.native_fns.put(a, "ReflectionMethod::getDeclaringClass", rmGetDeclaringClass);
    try vm.native_fns.put(a, "ReflectionMethod::getReturnType", rmGetReturnType);
    try vm.native_fns.put(a, "ReflectionMethod::isConstructor", rmIsConstructor);
    try vm.native_fns.put(a, "ReflectionMethod::isDestructor", rmIsDestructor);
    try vm.native_fns.put(a, "ReflectionMethod::getDocComment", rmGetDocComment);
    try vm.native_fns.put(a, "ReflectionMethod::getNumberOfParameters", rmGetNumberOfParameters);
    try vm.native_fns.put(a, "ReflectionMethod::getNumberOfRequiredParameters", rmGetNumberOfRequiredParameters);
    try vm.native_fns.put(a, "ReflectionMethod::setAccessible", reflectionNoop);
    try vm.native_fns.put(a, "ReflectionMethod::invoke", rmInvoke);
    try vm.native_fns.put(a, "ReflectionMethod::hasReturnType", rmHasReturnType);
    try vm.native_fns.put(a, "ReflectionMethod::hasTentativeReturnType", rmHasTentativeReturnType);
    try vm.native_fns.put(a, "ReflectionMethod::getTentativeReturnType", rmGetTentativeReturnType);
    try vm.native_fns.put(a, "ReflectionMethod::invokeArgs", rmInvokeArgs);
    try vm.native_fns.put(a, "ReflectionMethod::isAbstract", rmIsAbstract);
    try vm.native_fns.put(a, "ReflectionMethod::isFinal", rmIsFinal);
    try vm.native_fns.put(a, "ReflectionMethod::isVariadic", rmIsVariadic);
    try vm.native_fns.put(a, "ReflectionMethod::isGenerator", rmIsGenerator);
    try vm.native_fns.put(a, "ReflectionMethod::returnsReference", rmReturnsReference);
    try vm.native_fns.put(a, "ReflectionMethod::getModifiers", rmGetModifiers);
    try vm.native_fns.put(a, "ReflectionMethod::getAttributes", rmGetAttributes);
    try vm.native_fns.put(a, "ReflectionMethod::getClosure", rmGetClosure);
    try vm.native_fns.put(a, "ReflectionMethod::getFileName", rmGetFileName);
    try vm.native_fns.put(a, "ReflectionMethod::getStartLine", rmGetStartLine);
    try vm.native_fns.put(a, "ReflectionMethod::getEndLine", rmGetEndLine);
    try vm.native_fns.put(a, "ReflectionMethod::getNamespaceName", reflectionEmptyString);
    try vm.native_fns.put(a, "ReflectionMethod::getShortName", rmGetName);
    try vm.native_fns.put(a, "ReflectionMethod::inNamespace", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionMethod::isInternal", rmIsInternal);
    try vm.native_fns.put(a, "ReflectionMethod::isUserDefined", rmIsUserDefined);
    try vm.native_fns.put(a, "ReflectionMethod::isDeprecated", rmIsDeprecated);
    try vm.native_fns.put(a, "ReflectionMethod::getStaticVariables", rmGetStaticVariables);
    try vm.native_fns.put(a, "ReflectionMethod::getExtension", rfGetExtension);
    try vm.native_fns.put(a, "ReflectionMethod::getPrototype", rmGetPrototype);
    try vm.native_fns.put(a, "ReflectionMethod::hasPrototype", rmHasPrototype);
    try vm.native_fns.put(a, "ReflectionMethod::getExtensionName", rfGetExtensionName);

    var rp_def = ClassDef{ .name = "ReflectionParameter" };
    try rp_def.interfaces.append(a, "Reflector");
    try rp_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try rp_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try rp_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rp_def.methods.put(a, "getType", .{ .name = "getType", .arity = 0 });
    try rp_def.methods.put(a, "isDefaultValueAvailable", .{ .name = "isDefaultValueAvailable", .arity = 0 });
    try rp_def.methods.put(a, "getDefaultValue", .{ .name = "getDefaultValue", .arity = 0 });
    try rp_def.methods.put(a, "isOptional", .{ .name = "isOptional", .arity = 0 });
    try rp_def.methods.put(a, "getPosition", .{ .name = "getPosition", .arity = 0 });
    try rp_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rp_def.methods.put(a, "isPassedByReference", .{ .name = "isPassedByReference", .arity = 0 });
    try rp_def.methods.put(a, "canBePassedByValue", .{ .name = "canBePassedByValue", .arity = 0 });
    try rp_def.methods.put(a, "hasType", .{ .name = "hasType", .arity = 0 });
    try rp_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rp_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rp_def.methods.put(a, "getDeclaringFunction", .{ .name = "getDeclaringFunction", .arity = 0 });
    try rp_def.methods.put(a, "isVariadic", .{ .name = "isVariadic", .arity = 0 });
    try rp_def.methods.put(a, "isPromoted", .{ .name = "isPromoted", .arity = 0 });
    try rp_def.methods.put(a, "getClass", .{ .name = "getClass", .arity = 0 });
    try rp_def.methods.put(a, "isArray", .{ .name = "isArray", .arity = 0 });
    try rp_def.methods.put(a, "isCallable", .{ .name = "isCallable", .arity = 0 });
    try rp_def.methods.put(a, "isDefaultValueConstant", .{ .name = "isDefaultValueConstant", .arity = 0 });
    try rp_def.methods.put(a, "getDefaultValueConstantName", .{ .name = "getDefaultValueConstantName", .arity = 0 });
    try vm.classes.put(a, "ReflectionParameter", rp_def);

    try vm.native_fns.put(a, "ReflectionParameter::__construct", rpConstructParam);
    try vm.native_fns.put(a, "ReflectionParameter::getName", rpGetName);
    try vm.native_fns.put(a, "ReflectionParameter::getType", rpGetType);
    try vm.native_fns.put(a, "ReflectionParameter::isDefaultValueAvailable", rpIsDefaultValueAvailable);
    try vm.native_fns.put(a, "ReflectionParameter::getDefaultValue", rpGetDefaultValue);
    try vm.native_fns.put(a, "ReflectionParameter::isOptional", rpIsOptional);
    try vm.native_fns.put(a, "ReflectionParameter::getPosition", rpGetPosition);
    try vm.native_fns.put(a, "ReflectionParameter::allowsNull", rpAllowsNull);
    try vm.native_fns.put(a, "ReflectionParameter::isPassedByReference", rpIsPassedByReference);
    try vm.native_fns.put(a, "ReflectionParameter::canBePassedByValue", rpCanBePassedByValue);
    try vm.native_fns.put(a, "ReflectionParameter::hasType", rpHasType);
    try vm.native_fns.put(a, "ReflectionParameter::getAttributes", rpGetAttributes);
    try vm.native_fns.put(a, "ReflectionParameter::getDeclaringClass", rpGetDeclaringClass);
    try vm.native_fns.put(a, "ReflectionParameter::getDeclaringFunction", rpGetDeclaringFunction);
    try vm.native_fns.put(a, "ReflectionParameter::isVariadic", rpIsVariadic);
    try vm.native_fns.put(a, "ReflectionParameter::isPromoted", rpIsPromoted);
    try vm.native_fns.put(a, "ReflectionParameter::getClass", rpGetClass);
    try vm.native_fns.put(a, "ReflectionParameter::isArray", rpIsArray);
    try vm.native_fns.put(a, "ReflectionParameter::isCallable", rpIsCallable);
    try vm.native_fns.put(a, "ReflectionParameter::isDefaultValueConstant", rpIsDefaultValueConstant);
    try vm.native_fns.put(a, "ReflectionParameter::getDefaultValueConstantName", rpGetDefaultValueConstantName);

    var rnt_def = ClassDef{ .name = "ReflectionNamedType", .parent = "ReflectionType" };
    try rnt_def.properties.append(a, .{ .name = "__type_name", .default = .{ .string = Value.String.borrowed("") } });
    try rnt_def.properties.append(a, .{ .name = "__nullable", .default = .{ .bool = false } });
    try rnt_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rnt_def.methods.put(a, "isBuiltin", .{ .name = "isBuiltin", .arity = 0 });
    try rnt_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rnt_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionNamedType", rnt_def);

    try vm.native_fns.put(a, "ReflectionNamedType::getName", rntGetName);
    try vm.native_fns.put(a, "ReflectionNamedType::isBuiltin", rntIsBuiltin);
    try vm.native_fns.put(a, "ReflectionNamedType::allowsNull", rntAllowsNull);
    try vm.native_fns.put(a, "ReflectionNamedType::__toString", rntToString);

    var rut_def = ClassDef{ .name = "ReflectionUnionType", .parent = "ReflectionType" };
    try rut_def.properties.append(a, .{ .name = "__type_str", .default = .{ .string = Value.String.borrowed("") } });
    try rut_def.properties.append(a, .{ .name = "__nullable", .default = .{ .bool = false } });
    try rut_def.methods.put(a, "getTypes", .{ .name = "getTypes", .arity = 0 });
    try rut_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rut_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionUnionType", rut_def);
    try vm.native_fns.put(a, "ReflectionUnionType::getTypes", rutGetTypes);
    try vm.native_fns.put(a, "ReflectionUnionType::allowsNull", rutAllowsNull);
    try vm.native_fns.put(a, "ReflectionUnionType::__toString", rutToString);

    var rit_def = ClassDef{ .name = "ReflectionIntersectionType", .parent = "ReflectionType" };
    try rit_def.properties.append(a, .{ .name = "__type_str", .default = .{ .string = Value.String.borrowed("") } });
    try rit_def.methods.put(a, "getTypes", .{ .name = "getTypes", .arity = 0 });
    try rit_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rit_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionIntersectionType", rit_def);
    try vm.native_fns.put(a, "ReflectionIntersectionType::getTypes", ritGetTypes);
    try vm.native_fns.put(a, "ReflectionIntersectionType::allowsNull", ritAllowsNull);
    try vm.native_fns.put(a, "ReflectionIntersectionType::__toString", ritToString);

    var re_def = ClassDef{ .name = "ReflectionEnum" };
    re_def.parent = "ReflectionClass";
    try re_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try re_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try re_def.methods.put(a, "isBacked", .{ .name = "isBacked", .arity = 0 });
    try re_def.methods.put(a, "getBackingType", .{ .name = "getBackingType", .arity = 0 });
    try re_def.methods.put(a, "getCases", .{ .name = "getCases", .arity = 0 });
    try re_def.methods.put(a, "getCase", .{ .name = "getCase", .arity = 1 });
    try re_def.methods.put(a, "hasCase", .{ .name = "hasCase", .arity = 1 });
    try vm.classes.put(a, "ReflectionEnum", re_def);
    try vm.native_fns.put(a, "ReflectionEnum::__construct", reConstruct);
    try vm.native_fns.put(a, "ReflectionEnum::isBacked", reIsBacked);
    try vm.native_fns.put(a, "ReflectionEnum::getBackingType", reGetBackingType);
    try vm.native_fns.put(a, "ReflectionEnum::getCases", reGetCases);
    try vm.native_fns.put(a, "ReflectionEnum::getCase", reGetCase);
    try vm.native_fns.put(a, "ReflectionEnum::hasCase", reHasCase);

    var reuc_def = ClassDef{ .name = "ReflectionEnumUnitCase", .parent = "ReflectionClassConstant" };
    try reuc_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try reuc_def.properties.append(a, .{ .name = "class", .default = .{ .string = Value.String.borrowed("") } });
    try reuc_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try reuc_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try reuc_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 0 });
    try vm.classes.put(a, "ReflectionEnumUnitCase", reuc_def);
    try vm.native_fns.put(a, "ReflectionEnumUnitCase::__construct", reucConstruct);
    try vm.native_fns.put(a, "ReflectionEnumUnitCase::getName", reucGetName);
    try vm.native_fns.put(a, "ReflectionEnumUnitCase::getValue", reucGetValue);

    var rebc_def = ClassDef{ .name = "ReflectionEnumBackedCase" };
    rebc_def.parent = "ReflectionEnumUnitCase";
    try rebc_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try rebc_def.properties.append(a, .{ .name = "class", .default = .{ .string = Value.String.borrowed("") } });
    try rebc_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try rebc_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rebc_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 0 });
    try rebc_def.methods.put(a, "getBackingValue", .{ .name = "getBackingValue", .arity = 0 });
    try vm.classes.put(a, "ReflectionEnumBackedCase", rebc_def);
    try vm.native_fns.put(a, "ReflectionEnumBackedCase::__construct", reucConstruct);
    try vm.native_fns.put(a, "ReflectionEnumBackedCase::getName", reucGetName);
    try vm.native_fns.put(a, "ReflectionEnumBackedCase::getValue", reucGetValue);
    try vm.native_fns.put(a, "ReflectionEnumBackedCase::getBackingValue", rebcGetBackingValue);

    var rf_def = ClassDef{ .name = "ReflectionFunction", .parent = "ReflectionFunctionAbstract" };
    try rf_def.constants.put(a, "IS_DEPRECATED", .{ .int = 2048 });
    try rf_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try rf_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try rf_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rf_def.methods.put(a, "getParameters", .{ .name = "getParameters", .arity = 0 });
    try rf_def.methods.put(a, "getReturnType", .{ .name = "getReturnType", .arity = 0 });
    try rf_def.methods.put(a, "getNumberOfParameters", .{ .name = "getNumberOfParameters", .arity = 0 });
    try rf_def.methods.put(a, "getNumberOfRequiredParameters", .{ .name = "getNumberOfRequiredParameters", .arity = 0 });
    try rf_def.methods.put(a, "isAnonymous", .{ .name = "isAnonymous", .arity = 0 });
    try rf_def.methods.put(a, "isClosure", .{ .name = "isClosure", .arity = 0 });
    try rf_def.methods.put(a, "isInternal", .{ .name = "isInternal", .arity = 0 });
    try rf_def.methods.put(a, "isUserDefined", .{ .name = "isUserDefined", .arity = 0 });
    try rf_def.methods.put(a, "isGenerator", .{ .name = "isGenerator", .arity = 0 });
    try rf_def.methods.put(a, "isVariadic", .{ .name = "isVariadic", .arity = 0 });
    try rf_def.methods.put(a, "returnsReference", .{ .name = "returnsReference", .arity = 0 });
    try rf_def.methods.put(a, "getStaticVariables", .{ .name = "getStaticVariables", .arity = 0 });
    try rf_def.methods.put(a, "getClosureScopeClass", .{ .name = "getClosureScopeClass", .arity = 0 });
    try rf_def.methods.put(a, "getClosure", .{ .name = "getClosure", .arity = 0 });
    try rf_def.methods.put(a, "getClosureThis", .{ .name = "getClosureThis", .arity = 0 });
    try rf_def.methods.put(a, "isStatic", .{ .name = "isStatic", .arity = 0 });
    try rf_def.methods.put(a, "hasReturnType", .{ .name = "hasReturnType", .arity = 0 });
    try rf_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rf_def.methods.put(a, "invoke", .{ .name = "invoke", .arity = 0 });
    try rf_def.methods.put(a, "invokeArgs", .{ .name = "invokeArgs", .arity = 1 });
    try rf_def.methods.put(a, "getFileName", .{ .name = "getFileName", .arity = 0 });
    try rf_def.methods.put(a, "getStartLine", .{ .name = "getStartLine", .arity = 0 });
    try rf_def.methods.put(a, "getEndLine", .{ .name = "getEndLine", .arity = 0 });
    try rf_def.methods.put(a, "getDocComment", .{ .name = "getDocComment", .arity = 0 });
    try rf_def.methods.put(a, "getNamespaceName", .{ .name = "getNamespaceName", .arity = 0 });
    try rf_def.methods.put(a, "getShortName", .{ .name = "getShortName", .arity = 0 });
    try rf_def.methods.put(a, "inNamespace", .{ .name = "inNamespace", .arity = 0 });
    try rf_def.methods.put(a, "getExtension", .{ .name = "getExtension", .arity = 0 });
    try rf_def.methods.put(a, "getExtensionName", .{ .name = "getExtensionName", .arity = 0 });
    try rf_def.methods.put(a, "isDeprecated", .{ .name = "isDeprecated", .arity = 0 });
    try rf_def.methods.put(a, "isDisabled", .{ .name = "isDisabled", .arity = 0 });
    try vm.classes.put(a, "ReflectionFunction", rf_def);

    try vm.native_fns.put(a, "ReflectionFunction::__construct", rfConstruct);
    try vm.native_fns.put(a, "ReflectionFunction::getName", rfGetName);
    try vm.native_fns.put(a, "ReflectionFunction::getParameters", rfGetParameters);
    try vm.native_fns.put(a, "ReflectionFunction::getReturnType", rfGetReturnType);
    try vm.native_fns.put(a, "ReflectionFunction::getNumberOfParameters", rfGetNumberOfParameters);
    try vm.native_fns.put(a, "ReflectionFunction::getNumberOfRequiredParameters", rfGetNumberOfRequiredParameters);
    try vm.native_fns.put(a, "ReflectionFunction::isAnonymous", rfIsAnonymous);
    try vm.native_fns.put(a, "ReflectionFunction::isClosure", rfIsAnonymous);
    try vm.native_fns.put(a, "ReflectionFunction::isInternal", rfIsInternal);
    try vm.native_fns.put(a, "ReflectionFunction::isUserDefined", rfIsUserDefined);
    try vm.native_fns.put(a, "ReflectionFunction::isGenerator", rfIsGenerator);
    try vm.native_fns.put(a, "ReflectionFunction::isVariadic", rfIsVariadic);
    try vm.native_fns.put(a, "ReflectionFunction::returnsReference", rfReturnsReference);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureScopeClass", rfGetClosureScopeClass);
    try vm.native_fns.put(a, "ReflectionFunction::getClosure", rfGetClosure);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureThis", rfGetClosureThis);
    try vm.native_fns.put(a, "ReflectionFunction::isStatic", rfIsStatic);
    try vm.native_fns.put(a, "ReflectionFunction::hasReturnType", rfHasReturnType);
    try vm.native_fns.put(a, "ReflectionFunction::getAttributes", rfGetAttributes);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureUsedVariables", rfGetClosureUsedVariables);
    try vm.native_fns.put(a, "ReflectionFunction::getStaticVariables", rfGetStaticVariables);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureCalledClass", rfGetClosureCalledClass);
    try vm.native_fns.put(a, "ReflectionFunction::invoke", rfInvoke);
    try vm.native_fns.put(a, "ReflectionFunction::invokeArgs", rfInvokeArgs);
    try vm.native_fns.put(a, "ReflectionFunction::getFileName", rfGetFileName);
    try vm.native_fns.put(a, "ReflectionFunction::getStartLine", rfGetStartLine);
    try vm.native_fns.put(a, "ReflectionFunction::getEndLine", rfGetEndLine);
    try vm.native_fns.put(a, "ReflectionFunction::getDocComment", rfGetDocComment);
    try vm.native_fns.put(a, "ReflectionFunction::getNamespaceName", rfGetNamespaceName);
    try vm.native_fns.put(a, "ReflectionFunction::getShortName", rfGetShortName);
    try vm.native_fns.put(a, "ReflectionFunction::inNamespace", rfInNamespace);
    try vm.native_fns.put(a, "ReflectionFunction::getExtension", rfGetExtension);
    try vm.native_fns.put(a, "ReflectionFunction::getExtensionName", rfGetExtensionName);
    try vm.native_fns.put(a, "ReflectionFunction::isDeprecated", rfIsDeprecated);
    try vm.native_fns.put(a, "ReflectionFunction::isDisabled", reflectionFalse);

    var rprop_def = ClassDef{ .name = "ReflectionProperty" };
    try rprop_def.interfaces.append(a, "Reflector");
    try rprop_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try rprop_def.properties.append(a, .{ .name = "class", .default = .{ .string = Value.String.borrowed("") } });
    try rprop_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try rprop_def.methods.put(a, "setAccessible", .{ .name = "setAccessible", .arity = 1 });
    try rprop_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 1 });
    try rprop_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rprop_def.methods.put(a, "getType", .{ .name = "getType", .arity = 0 });
    try rprop_def.methods.put(a, "getSettableType", .{ .name = "getSettableType", .arity = 0 });
    try rprop_def.methods.put(a, "isPublic", .{ .name = "isPublic", .arity = 0 });
    try rprop_def.methods.put(a, "isProtected", .{ .name = "isProtected", .arity = 0 });
    try rprop_def.methods.put(a, "isPrivate", .{ .name = "isPrivate", .arity = 0 });
    try rprop_def.methods.put(a, "getDefaultValue", .{ .name = "getDefaultValue", .arity = 0 });
    try rprop_def.methods.put(a, "hasDefaultValue", .{ .name = "hasDefaultValue", .arity = 0 });
    try rprop_def.methods.put(a, "isInitialized", .{ .name = "isInitialized", .arity = 1 });
    try rprop_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rprop_def.methods.put(a, "isDefault", .{ .name = "isDefault", .arity = 0 });
    try rprop_def.methods.put(a, "isDynamic", .{ .name = "isDynamic", .arity = 0 });
    try rprop_def.methods.put(a, "getMangledName", .{ .name = "getMangledName", .arity = 0 });
    try rprop_def.methods.put(a, "isReadOnly", .{ .name = "isReadOnly", .arity = 0 });
    // PHP 8.4 added the lowercase 'isReadonly' alias
    try rprop_def.methods.put(a, "isReadonly", .{ .name = "isReadonly", .arity = 0 });
    try rprop_def.methods.put(a, "setValue", .{ .name = "setValue", .arity = 2 });
    try rprop_def.methods.put(a, "getRawValue", .{ .name = "getRawValue", .arity = 1 });
    try rprop_def.methods.put(a, "setRawValue", .{ .name = "setRawValue", .arity = 2 });
    try rprop_def.methods.put(a, "setRawValueWithoutLazyInitialization", .{ .name = "setRawValueWithoutLazyInitialization", .arity = 2 });
    try rprop_def.methods.put(a, "isStatic", .{ .name = "isStatic", .arity = 0 });
    try rprop_def.methods.put(a, "isPromoted", .{ .name = "isPromoted", .arity = 0 });
    try rprop_def.methods.put(a, "hasType", .{ .name = "hasType", .arity = 0 });
    try rprop_def.methods.put(a, "getModifiers", .{ .name = "getModifiers", .arity = 0 });
    try rprop_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rprop_def.methods.put(a, "getDocComment", .{ .name = "getDocComment", .arity = 0 });
    try rprop_def.methods.put(a, "isVirtual", .{ .name = "isVirtual", .arity = 0 });
    // php8.4 asymmetric visibility methods
    try rprop_def.methods.put(a, "isPrivateSet", .{ .name = "isPrivateSet", .arity = 0 });
    try rprop_def.methods.put(a, "isProtectedSet", .{ .name = "isProtectedSet", .arity = 0 });
    try rprop_def.methods.put(a, "isFinal", .{ .name = "isFinal", .arity = 0 });
    try rprop_def.methods.put(a, "isAbstract", .{ .name = "isAbstract", .arity = 0 });
    try rprop_def.methods.put(a, "hasHooks", .{ .name = "hasHooks", .arity = 0 });
    try rprop_def.methods.put(a, "getHooks", .{ .name = "getHooks", .arity = 0 });
    try rprop_def.methods.put(a, "hasHook", .{ .name = "hasHook", .arity = 1 });
    try rprop_def.methods.put(a, "getHook", .{ .name = "getHook", .arity = 1 });
    try rprop_def.methods.put(a, "isLazy", .{ .name = "isLazy", .arity = 1 });
    try rprop_def.methods.put(a, "skipLazyInitialization", .{ .name = "skipLazyInitialization", .arity = 1 });
    try rprop_def.constants.put(a, "IS_STATIC", .{ .int = 16 });
    try rprop_def.constants.put(a, "IS_READONLY", .{ .int = 128 });
    try rprop_def.constants.put(a, "IS_PUBLIC", .{ .int = 1 });
    try rprop_def.constants.put(a, "IS_PROTECTED", .{ .int = 2 });
    try rprop_def.constants.put(a, "IS_PRIVATE", .{ .int = 4 });
    try rprop_def.constants.put(a, "IS_ABSTRACT", .{ .int = 64 });
    try rprop_def.constants.put(a, "IS_PROTECTED_SET", .{ .int = 2048 });
    try rprop_def.constants.put(a, "IS_PRIVATE_SET", .{ .int = 4096 });
    try rprop_def.constants.put(a, "IS_VIRTUAL", .{ .int = 512 });
    try rprop_def.constants.put(a, "IS_FINAL", .{ .int = 32 });
    try vm.classes.put(a, "ReflectionProperty", rprop_def);

    try vm.native_fns.put(a, "ReflectionProperty::__construct", rpConstruct);
    try vm.native_fns.put(a, "ReflectionProperty::setAccessible", reflectionNoop);
    try vm.native_fns.put(a, "ReflectionProperty::getValue", rpGetValue);
    try vm.native_fns.put(a, "ReflectionProperty::getRawValue", rpGetRawValue);
    try vm.native_fns.put(a, "ReflectionProperty::setValue", rpSetValue);
    try vm.native_fns.put(a, "ReflectionProperty::setRawValue", rpSetRawValue);
    try vm.native_fns.put(a, "ReflectionProperty::setRawValueWithoutLazyInitialization", rpSetWithoutLazy);
    try vm.native_fns.put(a, "ReflectionProperty::getName", rpropGetName);
    try vm.native_fns.put(a, "ReflectionProperty::getType", rpropGetType);
    try vm.native_fns.put(a, "ReflectionProperty::getSettableType", rpropGetSettableType);
    try vm.native_fns.put(a, "ReflectionProperty::isPublic", rpropIsPublic);
    try vm.native_fns.put(a, "ReflectionProperty::isProtected", rpropIsProtected);
    try vm.native_fns.put(a, "ReflectionProperty::isPrivate", rpropIsPrivate);
    try vm.native_fns.put(a, "ReflectionProperty::isPrivateSet", rpropIsPrivateSet);
    try vm.native_fns.put(a, "ReflectionProperty::isProtectedSet", rpropIsProtectedSet);
    try vm.native_fns.put(a, "ReflectionProperty::isFinal", rpropIsFinal);
    try vm.native_fns.put(a, "ReflectionProperty::isAbstract", rpropIsAbstract);
    try vm.native_fns.put(a, "ReflectionProperty::hasHooks", rpropHasHooks);
    try vm.native_fns.put(a, "ReflectionProperty::hasHook", rpropHasHook);
    try vm.native_fns.put(a, "ReflectionProperty::getHooks", rpropGetHooks);
    try vm.native_fns.put(a, "ReflectionProperty::getHook", rpropGetHook);
    try vm.native_fns.put(a, "ReflectionProperty::isLazy", rpIsLazy);
    try vm.native_fns.put(a, "ReflectionProperty::skipLazyInitialization", rpSkipLazy);
    try vm.native_fns.put(a, "ReflectionProperty::getDefaultValue", rpropGetDefaultValue);
    try vm.native_fns.put(a, "ReflectionProperty::hasDefaultValue", rpropHasDefaultValue);
    try vm.native_fns.put(a, "ReflectionProperty::isInitialized", rpropIsInitialized);
    try vm.native_fns.put(a, "ReflectionProperty::getDeclaringClass", rpropGetDeclaringClass);
    try vm.native_fns.put(a, "ReflectionProperty::isDefault", rpropIsDefault);
    try vm.native_fns.put(a, "ReflectionProperty::isDynamic", rpropIsDynamic);
    try vm.native_fns.put(a, "ReflectionProperty::getMangledName", rpropGetMangledName);
    try vm.native_fns.put(a, "ReflectionProperty::isReadOnly", rpropIsReadOnly);
    try vm.native_fns.put(a, "ReflectionProperty::isReadonly", rpropIsReadOnly);
    try vm.native_fns.put(a, "ReflectionProperty::isStatic", rpropIsStatic);
    try vm.native_fns.put(a, "ReflectionProperty::isPromoted", rpropIsPromoted);
    try vm.native_fns.put(a, "ReflectionProperty::hasType", rpropHasType);
    try vm.native_fns.put(a, "ReflectionProperty::getModifiers", rpropGetModifiers);
    try vm.native_fns.put(a, "ReflectionProperty::getAttributes", rpropGetAttributes);
    try vm.native_fns.put(a, "ReflectionProperty::getDocComment", rpropGetDocComment);
    try vm.native_fns.put(a, "ReflectionProperty::isVirtual", rpropIsVirtual);

    var ra_def = ClassDef{ .name = "ReflectionAttribute" };
    try ra_def.constants.put(a, "IS_INSTANCEOF", .{ .int = 2 });
    try ra_def.interfaces.append(a, "Reflector");
    try ra_def.constants.put(a, "IS_INSTANCEOF", .{ .int = 2 });
    try ra_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0, .visibility = .private });
    try ra_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try ra_def.methods.put(a, "getArguments", .{ .name = "getArguments", .arity = 0 });
    try ra_def.methods.put(a, "newInstance", .{ .name = "newInstance", .arity = 0 });
    try ra_def.methods.put(a, "getTarget", .{ .name = "getTarget", .arity = 0 });
    try ra_def.methods.put(a, "isRepeated", .{ .name = "isRepeated", .arity = 0 });
    try vm.classes.put(a, "ReflectionAttribute", ra_def);

    try vm.native_fns.put(a, "ReflectionAttribute::__construct", raConstruct);
    try vm.native_fns.put(a, "ReflectionAttribute::getName", raGetName);
    try vm.native_fns.put(a, "ReflectionAttribute::getArguments", raGetArguments);
    try vm.native_fns.put(a, "ReflectionAttribute::newInstance", raNewInstance);
    try vm.native_fns.put(a, "ReflectionAttribute::getTarget", raGetTarget);
    try vm.native_fns.put(a, "ReflectionAttribute::isRepeated", raIsRepeated);

    var rcc_def = ClassDef{ .name = "ReflectionClassConstant" };
    try rcc_def.interfaces.append(a, "Reflector");
    inline for (.{ .{ "IS_PUBLIC", 1 }, .{ "IS_PROTECTED", 2 }, .{ "IS_PRIVATE", 4 }, .{ "IS_FINAL", 32 } }) |constant| {
        try rcc_def.constants.put(a, constant[0], .{ .int = constant[1] });
    }
    try rcc_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try rcc_def.properties.append(a, .{ .name = "class", .default = .{ .string = Value.String.borrowed("") } });
    try rcc_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try rcc_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rcc_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 0 });
    try rcc_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rcc_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rcc_def.methods.put(a, "isPublic", .{ .name = "isPublic", .arity = 0 });
    try rcc_def.methods.put(a, "isProtected", .{ .name = "isProtected", .arity = 0 });
    try rcc_def.methods.put(a, "isPrivate", .{ .name = "isPrivate", .arity = 0 });
    try rcc_def.methods.put(a, "isFinal", .{ .name = "isFinal", .arity = 0 });
    try rcc_def.methods.put(a, "isEnumCase", .{ .name = "isEnumCase", .arity = 0 });
    try rcc_def.methods.put(a, "isDeprecated", .{ .name = "isDeprecated", .arity = 0 });
    try rcc_def.methods.put(a, "getType", .{ .name = "getType", .arity = 0 });
    try rcc_def.methods.put(a, "hasType", .{ .name = "hasType", .arity = 0 });
    try rcc_def.methods.put(a, "getModifiers", .{ .name = "getModifiers", .arity = 0 });
    try rcc_def.methods.put(a, "getDocComment", .{ .name = "getDocComment", .arity = 0 });
    try vm.classes.put(a, "ReflectionClassConstant", rcc_def);
    try vm.native_fns.put(a, "ReflectionClassConstant::getDocComment", rccGetDocComment);
    try vm.native_fns.put(a, "ReflectionClassConstant::isDeprecated", rccIsDeprecated);

    try vm.native_fns.put(a, "ReflectionClassConstant::__construct", rccConstruct);
    try vm.native_fns.put(a, "ReflectionClassConstant::getName", rccGetName);
    try vm.native_fns.put(a, "ReflectionClassConstant::getValue", rccGetValue);
    try vm.native_fns.put(a, "ReflectionClassConstant::getDeclaringClass", rccGetDeclaringClass);
    try vm.native_fns.put(a, "ReflectionClassConstant::getAttributes", rccGetAttributes);
    try vm.native_fns.put(a, "ReflectionClassConstant::isPublic", rccIsPublic);
    try vm.native_fns.put(a, "ReflectionClassConstant::isProtected", rccIsProtected);
    try vm.native_fns.put(a, "ReflectionClassConstant::isPrivate", rccIsPrivate);
    try vm.native_fns.put(a, "ReflectionClassConstant::isFinal", rccIsFinal);
    try vm.native_fns.put(a, "ReflectionClassConstant::isEnumCase", rccIsEnumCase);
    try vm.native_fns.put(a, "ReflectionClassConstant::getType", rccGetType);
    try vm.native_fns.put(a, "ReflectionClassConstant::hasType", rccHasType);
    try vm.native_fns.put(a, "ReflectionClassConstant::getModifiers", rccGetModifiers);

    var closure_def = ClassDef{ .name = "Closure", .is_final = true, .native_properties = closureProperties };
    inline for (.{
        .{ "bind", 2, true },
        .{ "bindTo", 1, false },
        .{ "call", 1, false },
        .{ "fromCallable", 1, true },
        .{ "getCurrent", 0, true },
        .{ "__invoke", 0, false },
    }) |method| {
        try closure_def.methods.put(a, method[0], .{ .name = method[0], .arity = method[1], .is_static = method[2] });
        try closure_def.method_order.append(a, method[0]);
    }
    try vm.classes.put(a, "Closure", closure_def);
    try vm.native_fns.put(a, "Closure::getCurrent", closureGetCurrent);
    try vm.native_fns.put(a, "Closure::bind", closureBind);
    try vm.native_fns.put(a, "Closure::bindTo", closureBindTo);
    try vm.native_fns.put(a, "Closure::call", closureCall);
    try vm.native_fns.put(a, "Closure::__invoke", closureInvoke);
    try vm.native_fns.put(a, "Closure::fromCallable", closureFromCallable);

    var rext_def = ClassDef{ .name = "ReflectionExtension" };
    try rext_def.interfaces.append(a, "Reflector");
    try rext_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    for ([_][]const u8{
        "__construct",   "getName",     "getVersion",    "getFunctions",    "getConstants",
        "getINIEntries", "getClasses",  "getClassNames", "getDependencies", "info",
        "isPersistent",  "isTemporary", "__toString",
    }) |method| try rext_def.methods.put(a, method, .{ .name = method, .arity = if (std.mem.eql(u8, method, "__construct")) 1 else 0 });
    try vm.classes.put(a, "ReflectionExtension", rext_def);

    var rzext_def = ClassDef{ .name = "ReflectionZendExtension" };
    try rzext_def.interfaces.append(a, "Reflector");
    try rzext_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    for ([_][]const u8{ "__construct", "__toString", "getName", "getVersion", "getAuthor", "getURL", "getCopyright" }) |method| {
        try rzext_def.methods.put(a, method, .{ .name = method, .arity = if (std.mem.eql(u8, method, "__construct")) 1 else 0 });
    }
    try vm.classes.put(a, "ReflectionZendExtension", rzext_def);
    try vm.native_fns.put(a, "ReflectionZendExtension::__construct", rzextConstruct);
    try vm.native_fns.put(a, "ReflectionExtension::__construct", rextConstruct);
    try vm.native_fns.put(a, "ReflectionExtension::getName", rextGetName);
    try vm.native_fns.put(a, "ReflectionExtension::getVersion", rextGetVersion);
    try vm.native_fns.put(a, "ReflectionExtension::getFunctions", rextGetFunctions);
    try vm.native_fns.put(a, "ReflectionExtension::getConstants", rextGetConstants);
    try vm.native_fns.put(a, "ReflectionExtension::getINIEntries", rextGetIniEntries);
    try vm.native_fns.put(a, "ReflectionExtension::getClasses", rextGetClasses);
    try vm.native_fns.put(a, "ReflectionExtension::getClassNames", rextGetClassNames);
    try vm.native_fns.put(a, "ReflectionExtension::getDependencies", rextGetDependencies);
    try vm.native_fns.put(a, "ReflectionExtension::info", rextInfo);
    try vm.native_fns.put(a, "ReflectionExtension::isPersistent", reflectionTrue);
    try vm.native_fns.put(a, "ReflectionExtension::isTemporary", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionExtension::__toString", rextToString);

    // virtual ClassDefs for builtin tagged-value types so ReflectionClass(name) succeeds.
    // Generator and Fiber are runtime concepts, not stored as PhpObject, but PHP exposes
    // them via Reflection. Empty methods table is fine - dispatch handles them separately.
    var generator_def = ClassDef{ .name = "Generator", .is_final = true };
    try generator_def.interfaces.append(a, "Iterator");
    try generator_def.interfaces.append(a, "Traversable");
    try vm.classes.put(a, "Generator", generator_def);
    try vm.classes.put(a, "Fiber", ClassDef{ .name = "Fiber" });

    var rref_def = ClassDef{ .name = "ReflectionReference", .is_final = true };
    try rref_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0, .visibility = .private });
    try rref_def.methods.put(a, "fromArrayElement", .{ .name = "fromArrayElement", .arity = 2, .is_static = true });
    try rref_def.methods.put(a, "getId", .{ .name = "getId", .arity = 0 });
    try vm.classes.put(a, "ReflectionReference", rref_def);

    try vm.native_fns.put(a, "ReflectionReference::fromArrayElement", rrefFromArrayElement);
    try vm.native_fns.put(a, "ReflectionReference::getId", rrefGetId);

    // ReflectionGenerator wraps a Generator value and exposes the currently-
    // executing position (file / line / function). zphp's Generator carries
    // its compiled function + ip so we can derive everything from there
    var rg_def = ClassDef{ .name = "ReflectionGenerator" };
    try rg_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try rg_def.methods.put(a, "getExecutingLine", .{ .name = "getExecutingLine", .arity = 0 });
    try rg_def.methods.put(a, "getExecutingFile", .{ .name = "getExecutingFile", .arity = 0 });
    try rg_def.methods.put(a, "getFunction", .{ .name = "getFunction", .arity = 0 });
    try rg_def.methods.put(a, "getThis", .{ .name = "getThis", .arity = 0 });
    try rg_def.methods.put(a, "getExecutingGenerator", .{ .name = "getExecutingGenerator", .arity = 0 });
    try rg_def.methods.put(a, "getTrace", .{ .name = "getTrace", .arity = 0 });
    try rg_def.methods.put(a, "isClosed", .{ .name = "isClosed", .arity = 0 });
    try vm.classes.put(a, "ReflectionGenerator", rg_def);
    try vm.native_fns.put(a, "ReflectionGenerator::__construct", rgConstruct);
    try vm.native_fns.put(a, "ReflectionGenerator::getExecutingLine", rgGetExecutingLine);
    try vm.native_fns.put(a, "ReflectionGenerator::getExecutingFile", rgGetExecutingFile);
    try vm.native_fns.put(a, "ReflectionGenerator::getFunction", rgGetFunction);
    try vm.native_fns.put(a, "ReflectionGenerator::getThis", rgGetThis);
    try vm.native_fns.put(a, "ReflectionGenerator::getExecutingGenerator", rgGetExecutingGenerator);
    try vm.native_fns.put(a, "ReflectionGenerator::getTrace", rgGetTrace);
    try vm.native_fns.put(a, "ReflectionGenerator::isClosed", rgIsClosed);

    var rfib_def = ClassDef{ .name = "ReflectionFiber" };
    try rfib_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try rfib_def.methods.put(a, "getExecutingLine", .{ .name = "getExecutingLine", .arity = 0 });
    try rfib_def.methods.put(a, "getExecutingFile", .{ .name = "getExecutingFile", .arity = 0 });
    try rfib_def.methods.put(a, "getCallable", .{ .name = "getCallable", .arity = 0 });
    try rfib_def.methods.put(a, "getFiber", .{ .name = "getFiber", .arity = 0 });
    try rfib_def.methods.put(a, "getTrace", .{ .name = "getTrace", .arity = 0 });
    try vm.classes.put(a, "ReflectionFiber", rfib_def);
    try vm.native_fns.put(a, "ReflectionFiber::__construct", rfibConstruct);
    try vm.native_fns.put(a, "ReflectionFiber::getExecutingLine", rfibGetExecutingLine);
    try vm.native_fns.put(a, "ReflectionFiber::getExecutingFile", rfibGetExecutingFile);
    try vm.native_fns.put(a, "ReflectionFiber::getCallable", rfibGetCallable);
    try vm.native_fns.put(a, "ReflectionFiber::getFiber", rfibGetFiber);
    try vm.native_fns.put(a, "ReflectionFiber::getTrace", rfibGetTrace);

    try @import("reflection_string.zig").register(vm, a);

    // php leaves clone_obj NULL for every reflector
    for ([_][]const u8{ "ReflectionClass", "ReflectionFunctionAbstract", "ReflectionParameter", "ReflectionType", "ReflectionProperty", "ReflectionClassConstant", "ReflectionExtension", "ReflectionZendExtension", "ReflectionReference", "ReflectionAttribute", "ReflectionGenerator", "ReflectionFiber", "ReflectionConstant" }) |name| {
        if (vm.classes.getPtr(name)) |cls| cls.uncloneable = true;
    }
}

fn rextConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = try zpp.str(ctx, "ReflectionExtension::__construct", args, 0, "name");
    const canonical = extensionName(name) orelse {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Extension \"{s}\" does not exist", .{name});
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    };
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(canonical) });
    return NativeResult.scalar(.null);
}

// the module name of a loaded extension, named in any case
pub fn extensionName(name: []const u8) ?[]const u8 {
    for (@import("types.zig").SUPPORTED_EXTENSIONS) |ext| if (std.ascii.eqlIgnoreCase(ext, name)) return ext;
    for (@import("../extension.zig").loaded()) |ext| if (std.ascii.eqlIgnoreCase(ext.name, name)) return ext.name;
    return null;
}

fn enumIsBacked(vm: *VM, class_name: []const u8) bool {
    const cls = vm.classes.get(class_name) orelse return false;
    return cls.backed_type != .none;
}

fn rextGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rextGetVersion(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal(php_version.string);
}

fn reflectionEmptyArray(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

fn reflectionTrue(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

// php_info_print_module in text mode: the module's heading, the lines its
// MINFO prints, and its ini entries
fn rextInfo(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(ctx.allocator);
    try out.print(ctx.allocator, "\n{s}\n\n", .{name});
    if (std.mem.eql(u8, name, "Reflection")) {
        try out.appendSlice(ctx.allocator, "Reflection => enabled\n");
    } else if (std.mem.eql(u8, name, "date")) {
        const zone = try ctx.vm.callByName("date_default_timezone_get", &.{});
        try out.print(ctx.allocator, "date/time support => enabled\ntimelib version => 2022.17\n\"Olson\" Timezone Database Version => 0.system\nTimezone Database => internal\nDefault timezone => {s}\n", .{if (zone == .string) zone.string.bytes() else "UTC"});
    } else {
        try out.print(ctx.allocator, "{s} support => enabled\n", .{name});
    }
    var first = true;
    for (extensions.ini) |pair| {
        const entry = pair[0];
        if (!std.mem.eql(u8, pair[1], name)) continue;
        if (first) try out.appendSlice(ctx.allocator, "\nDirective => Local Value => Master Value\n");
        first = false;
        const v = try ctx.vm.callByName("ini_get", &.{.{ .string = Value.String.borrowed(entry) }});
        const text = if (v == .string) (if (v.string.bytes().len == 0) "no value" else v.string.bytes()) else "no value";
        try out.print(ctx.allocator, "{s} => {s} => {s}\n", .{ entry, text, text });
    }
    try ctx.vm.output.appendSlice(ctx.allocator, out.items);
    return NativeResult.scalar(.null);
}

fn extensionOfThis(ctx: *NativeContext) ?[]const u8 {
    const this = getThis(ctx) orelse return null;
    return if (this.get("name") == .string) this.get("name").string.bytes() else null;
}

fn rextGetFunctions(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const ext = extensionOfThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    for (extensions.functions.keys(), extensions.functions.values()) |name, owner| {
        if (!std.mem.eql(u8, owner, ext)) continue;
        const canonical = ctx.vm.canonicalFunctionName(name) orelse continue;
        const obj = try ctx.createObject("ReflectionFunction");
        try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(canonical) });
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(canonical) }, .{ .object = obj });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rextGetClasses(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return extensionClasses(ctx, true);
}

fn rextGetClassNames(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return extensionClasses(ctx, false);
}

fn extensionClasses(ctx: *NativeContext, objects: bool) RuntimeError!NativeResult {
    const ext = extensionOfThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    for (extensions.class_order) |name| {
        const owner = extensions.classes.get(name) orelse continue;
        if (!std.mem.eql(u8, owner, ext)) continue;
        if (!ctx.vm.classes.contains(name) and !ctx.vm.interfaces.contains(name) and !ctx.vm.traits.contains(name)) continue;
        const declared = try ctx.vm.stableClassName(ctx.vm.declaredClassName(name));
        const key: Value = .{ .string = Value.String.borrowed(declared) };
        if (objects) {
            const is_enum = if (ctx.vm.classes.get(declared)) |cd| cd.is_enum else false;
            const obj = try ctx.createObject(if (is_enum) "ReflectionEnum" else "ReflectionClass");
            try obj.set(ctx.allocator, "name", key);
            try obj.set(ctx.allocator, "__is_interface", .{ .bool = ctx.vm.interfaces.contains(declared) });
            try obj.set(ctx.allocator, "__is_trait", .{ .bool = ctx.vm.traits.contains(declared) });
            try arr.set(ctx.allocator, .{ .string = key.string }, .{ .object = obj });
        } else {
            try arr.append(ctx.allocator, key);
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rextGetConstants(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const ext = extensionOfThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    const all = try ctx.vm.callByName("get_defined_constants", &.{});
    if (all != .array) return NativeResult.borrowed(.{ .array = arr });
    for (all.array.entries.items) |entry| {
        if (entry.key != .string) continue;
        const owner = extensions.constants.get(entry.key.string.bytes()) orelse continue;
        if (!std.mem.eql(u8, owner, ext)) continue;
        try arr.set(ctx.allocator, entry.key, entry.value);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rextGetIniEntries(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const ext = extensionOfThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    for (extensions.ini) |pair| {
        const entry = pair[0];
        if (!std.mem.eql(u8, pair[1], ext)) continue;
        const v = try ctx.vm.callByName("ini_get", &.{.{ .string = Value.String.borrowed(entry) }});
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(entry) }, if (v == .string) v else .null);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rextGetDependencies(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const ext = extensionOfThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    for (extensions.dependencies) |dep| {
        if (!std.mem.eql(u8, dep[0], ext)) continue;
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(dep[1]) }, .{ .string = Value.String.borrowed(dep[2]) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// the ReflectionExtension of an extension name, or null for none
fn extensionObject(ctx: *NativeContext, name: ?[]const u8) RuntimeError!NativeResult {
    const ext = name orelse return NativeResult.scalar(.null);
    const obj = try ctx.createObject("ReflectionExtension");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(ext) });
    return NativeResult.borrowed(.{ .object = obj });
}

fn extensionNameResult(name: ?[]const u8) NativeResult {
    const ext = name orelse return NativeResult.scalar(.{ .bool = false });
    return .{ .value = .{ .string = Value.String.borrowed(ext) } };
}

// the extension an internal class belongs to; a user class has none
fn classExtension(ctx: *NativeContext) ?[]const u8 {
    const this = getThis(ctx) orelse return null;
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return null;
    if (!isInternalClassName(ctx.vm, name)) return null;
    return extensions.classes.get(name);
}

fn functionExtension(ctx: *NativeContext) ?[]const u8 {
    const this = getThis(ctx) orelse return null;
    if (this.get("__declaring_class") == .string) {
        const declaring = this.get("__declaring_class").string.bytes();
        if (!isInternalClassName(ctx.vm, declaring)) return null;
        return extensions.classes.get(declaring);
    }
    const key = functionKey(this);
    if (key != .string or ctx.vm.functions.contains(key.string.bytes())) return null;
    return extensions.functions.get(key.string.bytes());
}

fn constantExtension(ctx: *NativeContext) ?[]const u8 {
    const this = getThis(ctx) orelse return null;
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return null;
    return extensions.constants.get(name);
}

fn rcGetExtension(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return extensionObject(ctx, classExtension(ctx));
}
fn rcGetExtensionName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return extensionNameResult(classExtension(ctx));
}
fn rfGetExtension(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return extensionObject(ctx, functionExtension(ctx));
}
fn rfGetExtensionName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return extensionNameResult(functionExtension(ctx));
}
fn rconstGetExtension(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return extensionObject(ctx, constantExtension(ctx));
}
fn rconstGetExtensionName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return extensionNameResult(constantExtension(ctx));
}

// php's isIterable: an instantiable class implementing Traversable
fn rcIsIterable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.interfaces.contains(name) or ctx.vm.traits.contains(name)) return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.is_abstract) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = ctx.vm.isInstanceOf(name, "Traversable") });
}

fn rextToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return rextGetName(ctx, &.{});
}

pub fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

// php's zend_parse_parameters for the reflection natives: weak-mode
// coercion, the null deprecation, and the TypeError wording
const zpp = struct {
    fn typeError(ctx: *NativeContext, label: []const u8, i: usize, pname: []const u8, expected: []const u8, v: Value) RuntimeError {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #{d} (${s}) must be of type {s}, {s} given", .{ label, i + 1, pname, expected, v.valueName() });
        defer ctx.allocator.free(msg);
        _ = try ctx.vm.throwBuiltinException("TypeError", msg);
        return error.RuntimeError;
    }

    fn nullDeprecated(ctx: *NativeContext, label: []const u8, i: usize, pname: []const u8, expected: []const u8) RuntimeError!void {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Passing null to parameter #{d} (${s}) of type {s} is deprecated", .{ label, i + 1, pname, expected });
        defer ctx.allocator.free(msg);
        try ctx.vm.raiseError(VM.E_DEPRECATED, msg);
    }

    // a scalar as the string a string parameter receives, null when the
    // value can't be one
    fn scalarString(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, expected: []const u8) RuntimeError!?[]const u8 {
        const v = args[i];
        switch (v) {
            .string => |str_v| return str_v.bytes(),
            .int, .float, .bool => {
                var buf: std.ArrayListUnmanaged(u8) = .empty;
                defer buf.deinit(ctx.allocator);
                try v.format(&buf, ctx.allocator);
                return try ctx.vm.internName(buf.items);
            },
            .null => {
                try nullDeprecated(ctx, label, i, pname, expected);
                return "";
            },
            .object => |o| if (ctx.vm.hasMethod(o.class_name, "__toString")) {
                const r = try ctx.vm.callMethod(o, "__toString", &.{});
                defer ctx.vm.releaseValue(r);
                if (r == .string) return try ctx.vm.internName(r.string.bytes());
                return error.RuntimeError;
            },
            else => {},
        }
        return null;
    }

    fn str(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError![]const u8 {
        return (try scalarString(ctx, label, args, i, pname, "string")) orelse typeError(ctx, label, i, pname, "string", args[i]);
    }

    // Z_PARAM_OBJ_OR_STR: an object, or a string
    fn objOrStr(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!Value {
        if (args[i] == .object or isClosureValue(args[i])) return args[i];
        const text = (try scalarString(ctx, label, args, i, pname, "object|string")) orelse return typeError(ctx, label, i, pname, "object|string", args[i]);
        return .{ .string = Value.String.borrowed(text) };
    }

    // Z_PARAM_STR_OR_NULL
    fn strOrNull(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!?[]const u8 {
        if (i >= args.len or args[i] == .null) return null;
        return (try scalarString(ctx, label, args, i, pname, "?string")) orelse typeError(ctx, label, i, pname, "?string", args[i]);
    }

    // "?object" / "o!"
    fn optObject(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!?*PhpObject {
        if (i >= args.len) return null;
        return switch (args[i]) {
            .object => |o| o,
            .null => null,
            else => typeError(ctx, label, i, pname, "?object", args[i]),
        };
    }

    fn array(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8) RuntimeError!*PhpArray {
        if (args[i] == .array) return args[i].array;
        return typeError(ctx, label, i, pname, "array", args[i]);
    }

    fn long(ctx: *NativeContext, label: []const u8, args: []const Value, i: usize, pname: []const u8, nullable: bool) RuntimeError!?i64 {
        const v = args[i];
        switch (v) {
            .int => |n| return n,
            .bool => |b| return @intFromBool(b),
            .float => |f| if (std.math.isFinite(f) and @floor(f) == f and f >= -9.2233720368547758e18 and f < 9.2233720368547758e18) return @intFromFloat(f),
            .string => |sv| if (Value.isNumericString(sv.bytes())) {
                const as_float = Value.toFloat(v);
                if (@floor(as_float) == as_float) return Value.toInt(v);
            },
            .null => {
                if (nullable) return null;
                try nullDeprecated(ctx, label, i, pname, "int");
                return 0;
            },
            else => {},
        }
        return typeError(ctx, label, i, pname, if (nullable) "?int" else "int", v);
    }
};

// zend_lookup_class: a class, interface, trait or enum by name, autoloading
// it; the declared spelling, or null
fn lookupClass(ctx: *NativeContext, raw: []const u8) RuntimeError!?[]const u8 {
    const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    if (name.len == 0) return null;
    // a name with a nul byte (an anonymous class) is never autoloaded
    if (std.mem.indexOfScalar(u8, name, 0) == null and !ctx.vm.classes.contains(name) and !ctx.vm.interfaces.contains(name) and !ctx.vm.traits.contains(name)) {
        try ctx.vm.tryAutoload(name);
        if (ctx.vm.pending_exception != null) return error.RuntimeError;
    }
    if (!ctx.vm.classes.contains(name) and !ctx.vm.interfaces.contains(name) and !ctx.vm.traits.contains(name)) return null;
    return try ctx.vm.stableClassName(ctx.vm.declaredClassName(name));
}

// a closure as natives receive it: an instance name, or a Closure object
pub fn isClosureValue(v: Value) bool {
    if (v.closureName() != null) return true;
    return switch (v) {
        .string => |name| std.mem.startsWith(u8, name.bytes(), "__closure_"),
        .object => |o| std.mem.eql(u8, o.class_name, "Closure"),
        else => false,
    };
}

// the class an object|string argument names, or php's ReflectionException
fn classArgument(ctx: *NativeContext, v: Value) RuntimeError![]const u8 {
    if (isClosureValue(v)) return "Closure";
    if (v == .object) return v.object.class_name;
    const text = v.string.bytes();
    return (try lookupClass(ctx, text)) orelse {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" does not exist", .{text});
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    };
}

// php's zend_reflection_class_factory: a ReflectionEnum for an enum
pub fn classObject(ctx: *NativeContext, name: []const u8) RuntimeError!*PhpObject {
    const is_enum = if (ctx.vm.classes.get(name)) |cd| cd.is_enum else false;
    const obj = try ctx.createObject(if (is_enum) "ReflectionEnum" else "ReflectionClass");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(try ctx.vm.stableClassName(ctx.vm.declaredClassName(name))) });
    try obj.set(ctx.allocator, "__is_interface", .{ .bool = ctx.vm.interfaces.contains(name) });
    try obj.set(ctx.allocator, "__is_trait", .{ .bool = ctx.vm.traits.contains(name) });
    return obj;
}

fn throwReflection(ctx: *NativeContext, msg: []const u8) RuntimeError {
    _ = ctx.vm.throwBuiltinException("ReflectionException", msg) catch {};
    return error.RuntimeError;
}

fn isBuiltinType(name: []const u8) bool {
    const builtins = [_][]const u8{
        "int",   "string", "bool",  "float", "array",  "callable",
        "null",  "void",   "never", "mixed", "object", "iterable",
        "false", "true",
    };
    for (builtins) |b| {
        if (std.ascii.eqlIgnoreCase(name, b)) return true;
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
    try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed(clean_name) });
    try obj.set(ctx.allocator, "__nullable", .{ .bool = is_nullable });
    return obj;
}

// the type objects a union hands out borrow from this text, so it lives as
// long as the request, as the declarations' own type strings do
pub fn canonicalUnion(ctx: *NativeContext, text: []const u8, self_class: ?[]const u8) ![]const u8 {
    const t = php_types.parse(ctx.allocator, text, self_class, null) catch return text;
    defer t.deinit(ctx.allocator);
    const formatted = try php_types.format(ctx.allocator, t);
    errdefer ctx.allocator.free(formatted);
    try ctx.vm.strings.append(ctx.allocator, formatted);
    return formatted;
}

fn createTypeObj(ctx: *NativeContext, type_name: []const u8, nullable: bool, self_class: ?[]const u8) !*PhpObject {
    var clean = type_name;
    var is_nullable = nullable;
    if (clean.len > 0 and clean[0] == '?') {
        clean = clean[1..];
        is_nullable = true;
    }
    // PHP resolves 'self' / 'parent' at the class definition site but keeps
    // 'static' literal so reflection callers see the late-binding type
    if (self_class) |sc| {
        if (std.mem.eql(u8, clean, "self")) clean = sc;
    }
    if (std.mem.indexOfScalar(u8, clean, '|') != null) {
        // detect "T|null" / "null|T" - PHP normalizes to nullable named type
        var has_null = false;
        var non_null_count: usize = 0;
        var only_non_null: []const u8 = "";
        var it = std.mem.splitScalar(u8, clean, '|');
        while (it.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " ");
            if (std.ascii.eqlIgnoreCase(trimmed, "null")) {
                has_null = true;
            } else {
                non_null_count += 1;
                only_non_null = trimmed;
            }
        }
        // collapse `T|null` to a nullable named type only when T is a simple
        // type. PHP keeps `(I1&I2)|null` as a ReflectionUnionType (DNF form)
        const non_null_is_intersection = std.mem.indexOfScalar(u8, only_non_null, '&') != null or
            (only_non_null.len > 0 and only_non_null[0] == '(');
        if (has_null and non_null_count == 1 and !non_null_is_intersection) {
            var resolved = only_non_null;
            if (self_class) |sc| {
                if (std.mem.eql(u8, resolved, "self")) resolved = sc;
            }
            return createNamedTypeObj(ctx, resolved, true);
        }
        const obj = try ctx.createObject("ReflectionUnionType");
        // printed as php's zend_type_to_string orders a union
        try obj.set(ctx.allocator, "__type_str", .{ .string = Value.String.borrowed(try canonicalUnion(ctx, clean, self_class)) });
        if (has_null) is_nullable = true;
        try obj.set(ctx.allocator, "__nullable", .{ .bool = is_nullable });
        try obj.set(ctx.allocator, "__self_class", .{ .string = Value.String.borrowed(self_class orelse "") });
        return obj;
    }
    if (std.mem.indexOfScalar(u8, clean, '&') != null) {
        const obj = try ctx.createObject("ReflectionIntersectionType");
        try obj.set(ctx.allocator, "__type_str", .{ .string = Value.String.borrowed(clean) });
        return obj;
    }
    return createNamedTypeObj(ctx, clean, is_nullable);
}

fn buildMethodObj(ctx: *NativeContext, class_name: []const u8, method_name: []const u8, info: ClassDef.MethodInfo, declaring_class: []const u8) !*PhpObject {
    const obj = try ctx.createObject("ReflectionMethod");
    // $class is the class declaring the method, as php's method->common.scope;
    // the class it was asked about stays in __class (php's intern->ce)
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(method_name) });
    try obj.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(declaring_class) });
    try obj.set(ctx.allocator, "__class", .{ .string = Value.String.borrowed(class_name) });
    try obj.set(ctx.allocator, "__declaring_class", .{ .string = Value.String.borrowed(declaring_class) });
    try obj.set(ctx.allocator, "__is_static", .{ .bool = info.is_static });
    try obj.set(ctx.allocator, "__visibility", .{ .int = @backingInt(info.visibility) });

    // look up ObjFunction for parameter info
    var buf: [256]u8 = undefined;
    const key = class_names.memberKey(&buf, declaring_class, method_name);
    if (ctx.vm.functions.get(key)) |func| {
        try obj.set(ctx.allocator, "__arity", .{ .int = func.arity });
        try obj.set(ctx.allocator, "__required_params", .{ .int = func.required_params });
    } else if (native_params.get(key)) |sig| {
        try obj.set(ctx.allocator, "__arity", .{ .int = @intCast(sig.params.len) });
        try obj.set(ctx.allocator, "__required_params", .{ .int = @intCast(nativeRequiredCount(sig)) });
    } else {
        try obj.set(ctx.allocator, "__arity", .{ .int = info.arity });
        try obj.set(ctx.allocator, "__required_params", .{ .int = info.arity });
    }
    return obj;
}

// find which class in the hierarchy actually declares a method
pub fn findDeclaringClass(vm: *VM, class_name: []const u8, method_name: []const u8) []const u8 {
    var current: []const u8 = class_name;
    var declaring: []const u8 = class_name;
    var buf: [256]u8 = undefined;
    while (true) {
        const key = class_names.memberKey(&buf, current, method_name);
        if (vm.functions.get(key) != null or vm.native_fns.get(key) != null) {
            declaring = current;
            break;
        }
        const cls = vm.classes.get(current) orelse break;
        current = cls.parent orelse break;
    }
    return declaring;
}

// a static property's metadata in the shape instance properties use
pub fn staticPropertyDef(cls: *const ClassDef, name: []const u8, default: Value) ClassDef.PropertyDef {
    const vis = cls.static_prop_visibility.get(name) orelse .public;
    const set_vis = cls.static_prop_set_visibility.get(name);
    return .{
        .name = name,
        // the value an uninitialized typed static property holds is no default
        .default = if (default == .undef) .null else default,
        .has_default = default != .undef,
        .visibility = vis,
        .set_visibility = set_vis orelse vis,
        .has_set_visibility = set_vis != null,
        .type_str = cls.static_prop_types.get(name) orelse "",
        .is_final = cls.static_prop_final.contains(name),
    };
}

const PropertyDefResult = struct {
    prop: ClassDef.PropertyDef,
    declaring_class: []const u8,
    is_static: bool = false,
};

pub fn findPropertyDef(vm: *VM, class_name: []const u8, prop_name: []const u8) ?PropertyDefResult {
    if (vm.trait_props.get(class_name)) |props| {
        for (props) |prop| {
            if (std.mem.eql(u8, prop.name, prop_name)) return .{ .prop = prop, .declaring_class = class_name };
        }
    }
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = vm.classes.get(name) orelse break;
        for (cls.properties.items) |prop| {
            if (std.mem.eql(u8, prop.name, prop_name)) return .{ .prop = prop, .declaring_class = name };
        }
        if (cls.static_props.get(prop_name)) |v| {
            return .{ .prop = staticPropertyDef(&cls, prop_name, v), .declaring_class = name, .is_static = true };
        }
        if (vm.interfaces.get(name)) |iface| {
            for (iface.parents.items) |parent| {
                if (findPropertyDef(vm, parent, prop_name)) |result| return result;
            }
        }
        current = cls.parent;
    }
    return null;
}

fn buildPropertyObj(ctx: *NativeContext, class_name: []const u8, prop: ClassDef.PropertyDef, declaring_class: []const u8) !*PhpObject {
    return try buildPropertyObjStatic(ctx, class_name, prop, declaring_class, false);
}

fn buildPropertyObjStatic(
    ctx: *NativeContext,
    class_name: []const u8,
    prop: ClassDef.PropertyDef,
    declaring_class: []const u8,
    is_static: bool,
) !*PhpObject {
    const obj = try ctx.createObject("ReflectionProperty");
    try setPropertyReflection(ctx, obj, class_name, prop.name, .{ .prop = prop, .declaring_class = declaring_class, .is_static = is_static });
    return obj;
}

// php's reflection_property_factory: $class is the declaring class of a
// declared property and the reflected class (kept in __class, php's
// intern->ce) of a dynamic one, which has no __declaring_class
fn setPropertyReflection(ctx: *NativeContext, obj: *PhpObject, class_name: []const u8, prop_name: []const u8, found: ?PropertyDefResult) !void {
    const name = try ctx.vm.internName(prop_name);
    const ce = try ctx.vm.internName(class_name);
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(name) });
    try obj.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(if (found) |f| f.declaring_class else ce) });
    try obj.set(ctx.allocator, "__class", .{ .string = Value.String.borrowed(ce) });
    const result = found orelse {
        try obj.set(ctx.allocator, "__dynamic", .{ .bool = true });
        try obj.set(ctx.allocator, "__visibility", .{ .int = @backingInt(ClassDef.Visibility.public) });
        return;
    };
    const prop = result.prop;
    try obj.set(ctx.allocator, "__visibility", .{ .int = @backingInt(prop.visibility) });
    // an untyped property defaults to null; a typed one without a default
    // and a virtual one have none. a promoted property's default is never
    // its parameter's: null when untyped, none when typed
    const untyped = prop.type_str.len == 0;
    const effective_has_default = !prop.is_virtual and (if (prop.is_promoted) untyped else prop.has_default or untyped);
    try obj.set(ctx.allocator, "__has_default", .{ .bool = effective_has_default });
    try obj.set(ctx.allocator, "__default_value", if (effective_has_default and !prop.is_promoted) prop.default else .null);
    try obj.set(ctx.allocator, "__declaring_class", .{ .string = Value.String.borrowed(result.declaring_class) });
    try obj.set(ctx.allocator, "__set_visibility", .{ .int = @backingInt(prop.set_visibility) });
    try obj.set(ctx.allocator, "__has_set_visibility", .{ .bool = prop.has_set_visibility });
    try obj.set(ctx.allocator, "__is_readonly", .{ .bool = prop.is_readonly and !prop.readonly_undeclared });
    try obj.set(ctx.allocator, "__is_final", .{ .bool = prop.is_final });
    try obj.set(ctx.allocator, "__is_static", .{ .bool = result.is_static });
}

// php's lookup in ce->properties_info: a property the class declares or
// inherits, except an ancestor's private one
pub fn visiblePropertyDef(vm: *VM, class_name: []const u8, prop_name: []const u8) ?PropertyDefResult {
    const found = findPropertyDef(vm, class_name, prop_name) orelse return null;
    if (found.prop.visibility == .private and !std.ascii.eqlIgnoreCase(found.declaring_class, class_name)) return null;
    return found;
}

// whether the object holds a dynamic property of the name (one no visible
// declaration covers, as php's get_properties table lists it)
fn hasDynamicProperty(vm: *VM, obj: *PhpObject, prop_name: []const u8) bool {
    if (!obj.properties.contains(prop_name) or obj.isUnset(prop_name)) return false;
    if (object_properties.isInternalState(vm, obj, prop_name)) return false;
    return visiblePropertyDef(vm, obj.class_name, prop_name) == null;
}

fn hasAbstractMethodInChain(vm: *VM, class_name: []const u8, method_name: []const u8) bool {
    var current = class_name;
    while (true) {
        const cls = vm.classes.get(current) orelse return false;
        if (cls.methods.get(method_name)) |_| return true;
        if (cls.parent) |p| {
            current = p;
            continue;
        }
        return false;
    }
}

fn hasInterfaceMethod(vm: *VM, iface_name: []const u8, method_name: []const u8) bool {
    var buf: [256]u8 = undefined;
    const key = class_names.memberKey(&buf, iface_name, method_name);
    if (vm.functions.get(key) != null or vm.native_fns.get(key) != null) return true;
    const iface = vm.interfaces.get(iface_name) orelse return false;
    for (iface.methods.items) |m| {
        if (std.mem.eql(u8, m, method_name)) return true;
    }
    return false;
}

fn rcConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = try classObjectCtor(ctx, this, args, "ReflectionClass::__construct");
    return NativeResult.scalar(.null);
}

// reflection_class_object_ctor: a ReflectionObject takes only an object
fn classObjectCtor(ctx: *NativeContext, this: *PhpObject, args: []const Value, class_label: []const u8) RuntimeError![]const u8 {
    const is_object = ctx.vm.isInstanceOf(this.class_name, "ReflectionObject");
    const arg = if (is_object) blk: {
        if (args[0] != .object and !isClosureValue(args[0])) return zpp.typeError(ctx, "ReflectionObject::__construct", 0, "object", "object", args[0]);
        break :blk args[0];
    } else try zpp.objOrStr(ctx, class_label, args, 0, "objectOrClass");
    const class_name = try classArgument(ctx, arg);
    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(try ctx.vm.stableClassName(class_name)) });
    try this.set(ctx.allocator, "__is_interface", .{ .bool = ctx.vm.interfaces.contains(class_name) });
    try this.set(ctx.allocator, "__is_trait", .{ .bool = ctx.vm.traits.contains(class_name) });
    // a ReflectionObject keeps the object it reflects, whose dynamic
    // properties its string form lists
    if (is_object and (arg == .object or isClosureValue(arg))) try this.set(ctx.allocator, "__object", arg);
    return class_name;
}

fn rcGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rcGetConstructor(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    if (!ctx.vm.hasMethod(class_name, "__construct")) return NativeResult.scalar(.null);

    const declaring = findDeclaringClass(ctx.vm, class_name, "__construct");
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.null);
    const info = cls.methods.get("__construct") orelse ClassDef.MethodInfo{ .name = "__construct", .arity = 0 };
    const obj = try buildMethodObj(ctx, class_name, "__construct", info, declaring);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rcIsInstantiable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const is_iface = this.get("__is_interface");
    if (is_iface == .bool and is_iface.bool) return NativeResult.scalar(.{ .bool = false });
    const is_trait = this.get("__is_trait");
    if (is_trait == .bool and is_trait.bool) return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = true });
    if (cls.is_abstract or cls.is_enum) return NativeResult.scalar(.{ .bool = false });
    // php's Closure constructor is private; closures come from function syntax
    if (std.mem.eql(u8, class_name, "Closure")) return NativeResult.scalar(.{ .bool = false });
    // a constructor that isn't public can't be called from outside
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const c = ctx.vm.classes.get(name) orelse break;
        if (c.methods.get("__construct")) |ctor| return NativeResult.scalar(.{ .bool = ctor.visibility == .public });
        current = c.parent;
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn rcGetParentClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    const parent_name = cls.parent orelse return NativeResult.scalar(.{ .bool = false });

    const parent_obj = try classObject(ctx, parent_name);
    return NativeResult.borrowed(.{ .object = parent_obj });
}

fn rcImplementsInterface(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const iface = try reflectionClassArgument(ctx, args, "ReflectionClass::implementsInterface", "interface", "Interface");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (!ctx.vm.interfaces.contains(iface)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s} is not an interface", .{iface});
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    return NativeResult.scalar(.{ .bool = ctx.vm.isInstanceOf(class_name, iface) });
}

// Z_PARAM_OBJ_OF_CLASS_OR_STR(ReflectionClass): the class a ReflectionClass
// reflects, or one named by a string
fn reflectionClassArgument(ctx: *NativeContext, args: []const Value, label: []const u8, pname: []const u8, kind: []const u8) RuntimeError![]const u8 {
    if (args[0] == .object and ctx.vm.isInstanceOf(args[0].object.class_name, "ReflectionClass")) {
        const name = args[0].object.get("name");
        if (name != .string) {
            _ = try ctx.vm.throwBuiltinException("Error", "Internal error: Failed to retrieve the argument's reflection object");
            return error.RuntimeError;
        }
        return name.string.bytes();
    }
    const text = (if (args[0] == .object) null else try zpp.scalarString(ctx, label, args, 0, pname, "ReflectionClass|string")) orelse
        return zpp.typeError(ctx, label, 0, pname, "ReflectionClass|string", args[0]);
    return (try lookupClass(ctx, text)) orelse {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s} \"{s}\" does not exist", .{ kind, text });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    };
}

fn rcIsInstance(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const obj_class = args[0].object.class_name;
    if (std.ascii.eqlIgnoreCase(obj_class, class_name)) return NativeResult.scalar(.{ .bool = true });
    if (ctx.vm.interfaces.contains(class_name)) {
        var current: ?[]const u8 = obj_class;
        while (current) |name| {
            const cls = ctx.vm.classes.get(name) orelse break;
            for (cls.interfaces.items) |iface| {
                if (std.ascii.eqlIgnoreCase(iface, class_name)) return NativeResult.scalar(.{ .bool = true });
            }
            current = cls.parent;
        }
        return NativeResult.scalar(.{ .bool = false });
    }
    var current: ?[]const u8 = obj_class;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.parent) |p| {
            if (std.ascii.eqlIgnoreCase(p, class_name)) return NativeResult.scalar(.{ .bool = true });
            current = p;
        } else break;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcIsSubclassOf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const parent_name = try reflectionClassArgument(ctx, args, "ReflectionClass::isSubclassOf", "class", "Class");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = !std.ascii.eqlIgnoreCase(class_name, parent_name) and ctx.vm.isInstanceOf(class_name, parent_name) });
}

fn rcNewInstance(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return newInstanceWith(ctx, args, null, args.len);
}

fn rcNewInstanceArgs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const arr: ?*PhpArray = if (args.len >= 1) try zpp.array(ctx, "ReflectionClass::newInstanceArgs", args, 0, "args") else null;
    return newInstanceWith(ctx, &.{}, arr, if (arr) |a| a.entries.items.len else 0);
}

// the arguments a native passes on to a php call, bound as php's
// zend_call_function binds them: positional entries first, then named ones
// (string keys) placed on the callee's parameters, skipped parameters taking
// their defaults. the errors are php's: a positional entry after a named one,
// an unknown name, a name overwriting an argument, a required parameter left
// without one
const BoundArgs = struct {
    list: std.ArrayListUnmanaged(Value) = .empty,

    fn deinit(self: *BoundArgs, allocator: Allocator) void {
        self.list.deinit(allocator);
    }
};

fn raiseError(ctx: *NativeContext, class: []const u8, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    _ = try ctx.vm.throwBuiltinException(class, msg);
    return error.RuntimeError;
}

// func_key names the callee as vm.functions or the native signatures key it
// ("Class::method" or a function name); display is how messages name it
fn bindArguments(ctx: *NativeContext, func_key: []const u8, display: []const u8, positional: []const Value, named: ?*PhpArray) RuntimeError!BoundArgs {
    var bound: BoundArgs = .{};
    errdefer bound.deinit(ctx.allocator);
    try bound.list.appendSlice(ctx.allocator, positional);
    const arr = named orelse return bound;
    var saw_named = false;
    for (arr.entries.items) |entry| {
        const v = if (entry.ref) |r| r.* else entry.value;
        if (entry.key == .int) {
            if (saw_named) return raiseError(ctx, "Error", "Cannot use positional argument after named argument", .{});
            try bound.list.append(ctx.allocator, v);
        } else saw_named = true;
    }
    if (!saw_named) return bound;
    if (ctx.vm.functions.get(func_key)) |func| {
        const fixed: usize = if (func.is_variadic and func.arity > 0) func.arity - 1 else func.params.len;
        const given = bound.list.items.len;
        for (arr.entries.items) |entry| {
            if (entry.key != .string) continue;
            const name = entry.key.string.bytes();
            const index = for (func.params[0..@min(fixed, func.params.len)], 0..) |p, i| {
                if (std.mem.eql(u8, std.mem.trimStart(u8, p, "$"), name)) break i;
            } else return raiseError(ctx, "Error", "Unknown named parameter ${s}", .{name});
            if (index < given or (index < bound.list.items.len and bound.list.items[index] != .undef))
                return raiseError(ctx, "Error", "Named parameter ${s} overwrites previous argument", .{name});
            while (bound.list.items.len <= index) try bound.list.append(ctx.allocator, .undef);
            bound.list.items[index] = if (entry.ref) |r| r.* else entry.value;
        }
        for (bound.list.items, 0..) |*slot, i| {
            if (slot.* != .undef) continue;
            if (i >= func.required_params and i < func.defaults.len) {
                slot.* = try ctx.vm.resolveParamDefault(func, i);
                continue;
            }
            return raiseError(ctx, "ArgumentCountError", "{s}(): Argument #{d} (${s}) not passed", .{ display, i + 1, std.mem.trimStart(u8, func.params[i], "$") });
        }
        return bound;
    }
    if (native_params.get(func_key)) |sig| {
        var resolved: [256]Value = undefined;
        var sources: [256]vm_mod.RefSource = undefined;
        const placed = try ctx.vm.placeNativeNamedArgs(arr, sig.params, &resolved, &sources);
        if (placed.problem) |problem| {
            const class, const msg = try ctx.vm.namedArgProblemMessage(display, sig.params, problem);
            defer ctx.allocator.free(msg);
            _ = try ctx.vm.throwBuiltinException(class, msg);
            return error.RuntimeError;
        }
        bound.list.clearRetainingCapacity();
        try bound.list.appendSlice(ctx.allocator, resolved[0..placed.count]);
        return bound;
    }
    for (arr.entries.items) |entry| if (entry.key == .string)
        return raiseError(ctx, "Error", "Unknown named parameter ${s}", .{entry.key.string.bytes()});
    return bound;
}

// the class's constructor as get_constructor finds it: its declaring class,
// declared name and visibility
const Constructor = struct { declaring: []const u8, name: []const u8, visibility: ClassDef.Visibility };

fn findConstructor(vm: *VM, class_name: []const u8) ?Constructor {
    if (!vm.hasMethod(class_name, "__construct")) return null;
    const name = declaredMethodName(vm, class_name, "__construct");
    const declaring = findDeclaringClass(vm, class_name, name);
    const vis = vm.findMethodVisibility(class_name, name);
    return .{ .declaring = declaring, .name = name, .visibility = vis.visibility };
}

// object_init_ex's refusals
fn checkInstantiable(ctx: *NativeContext, class_name: []const u8) RuntimeError!void {
    if (ctx.vm.traits.contains(class_name)) return raiseError(ctx, "Error", "Cannot instantiate trait {s}", .{class_name});
    if (ctx.vm.interfaces.contains(class_name)) return raiseError(ctx, "Error", "Cannot instantiate interface {s}", .{class_name});
    if (ctx.vm.classes.get(class_name)) |cd| {
        if (cd.is_enum) return raiseError(ctx, "Error", "Cannot instantiate enum {s}", .{class_name});
        if (cd.is_abstract) return raiseError(ctx, "Error", "Cannot instantiate abstract class {s}", .{class_name});
    }
    if (std.mem.eql(u8, class_name, "Generator") or std.mem.eql(u8, class_name, "Closure")) {
        const what = if (std.mem.eql(u8, class_name, "Closure")) "Instantiation of class Closure is not allowed" else "The \"Generator\" class is reserved for internal use and cannot be manually instantiated";
        return raiseError(ctx, "Error", "{s}", .{what});
    }
}

// ReflectionClass::newInstance / newInstanceArgs
fn newInstanceWith(ctx: *NativeContext, positional: []const Value, named: ?*PhpArray, argc: usize) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    try checkInstantiable(ctx, class_name);
    const ctor = findConstructor(ctx.vm, class_name);
    if (ctor) |c| if (c.visibility != .public) return throwReflectionFmt(ctx, "Access to non-public constructor of class {s}", .{class_name});
    const obj = try ctx.vm.allocObject(.{ .class_name = try ctx.vm.stableClassName(class_name) });
    // full slot layout + per-instance default copies (walks the parent chain,
    // deep-clones array defaults)
    try ctx.vm.initObjectProperties(obj, class_name);
    const c = ctor orelse {
        if (argc > 0) {
            ctx.vm.releaseValue(.{ .object = obj });
            return throwReflectionFmt(ctx, "Class {s} does not have a constructor, so you cannot pass any constructor arguments", .{class_name});
        }
        return NativeResult.borrowed(.{ .object = obj });
    };
    var key_buf: [256]u8 = undefined;
    const key = class_names.memberKey(&key_buf, c.declaring, c.name);
    var bound = try bindArguments(ctx, key, key, positional, named);
    defer bound.deinit(ctx.allocator);
    // a call from internal code: php's too-few-arguments error names no
    // calling line
    const outer = ctx.vm.native_caller;
    ctx.vm.native_caller = .{ .name = "ReflectionClass::newInstance", .frames = ctx.vm.frame_count };
    defer ctx.vm.native_caller = outer;
    _ = try ctx.callMethod(obj, "__construct", bound.list.items);
    return NativeResult.borrowed(.{ .object = obj });
}

fn throwReflectionFmt(ctx: *NativeContext, comptime fmt: []const u8, args: anytype) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, fmt, args);
    defer ctx.allocator.free(msg);
    return throwReflection(ctx, msg);
}

fn rcGetMethods(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const filter: ?i64 = if (args.len >= 1 and args[0] == .int) args[0].int else null;

    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);
    // Closure's __invoke is listed last, reflecting the closure
    if (std.mem.eql(u8, class_name, "Closure")) try seen.put(ctx.allocator, "__invoke", {});

    // interface methods (declaration order, abstract by definition)
    if (ctx.vm.interfaces.get(class_name)) |iface| {
        for (iface.methods.items) |method_name| {
            if (std.mem.indexOf(u8, method_name, "$hook_") != null) continue;
            if (seen.contains(method_name)) continue;
            try seen.put(ctx.allocator, method_name, {});
            const info = ClassDef.MethodInfo{ .name = method_name, .arity = 0, .visibility = .public, .is_abstract = true };
            if (filter) |f| if (!methodMatchesFilter(info, f)) continue;
            const obj = try buildMethodObj(ctx, class_name, method_name, info, class_name);
            try arr.append(ctx.allocator, .{ .object = obj });
        }
        return NativeResult.borrowed(.{ .array = arr });
    }

    var current: ?[]const u8 = class_name;
    var depth: usize = 0;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        // iterate in declaration order when available; fall back to hash iteration
        if (cls.method_order.items.len > 0) {
            for (cls.method_order.items) |method_name| {
                const info = cls.methods.get(method_name) orelse continue;
                if (std.mem.indexOf(u8, method_name, "$hook_") != null) continue;
                if (depth > 0 and info.visibility == .private) continue;
                if (seen.contains(method_name)) continue;
                try seen.put(ctx.allocator, method_name, {});
                if (filter) |f| if (!methodMatchesFilter(info, f)) continue;
                const declaring = findDeclaringClass(ctx.vm, class_name, method_name);
                const obj = try buildMethodObj(ctx, class_name, method_name, info, declaring);
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        } else {
            var it = cls.methods.iterator();
            while (it.next()) |entry| {
                const method_name = entry.key_ptr.*;
                const info = entry.value_ptr.*;
                if (std.mem.indexOf(u8, method_name, "$hook_") != null) continue;
                if (depth > 0 and info.visibility == .private) continue;
                if (seen.contains(method_name)) continue;
                try seen.put(ctx.allocator, method_name, {});
                if (filter) |f| if (!methodMatchesFilter(info, f)) continue;
                const declaring = findDeclaringClass(ctx.vm, class_name, method_name);
                const obj = try buildMethodObj(ctx, class_name, method_name, info, declaring);
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        }
        current = cls.parent;
        depth += 1;
    }
    // the Closure class's __invoke reflects the closure's signature
    const reflected = this.get("__object");
    if (std.mem.eql(u8, class_name, "Closure") and (filter == null or filter.? & 1 != 0)) {
        const obj = try ctx.createObject("ReflectionMethod");
        try setClosureInvokeMethod(ctx, obj, if (reflected.closureName() != null) reflected else .null);
        try arr.append(ctx.allocator, .{ .object = obj });
    }
    // an abstract class inherits the interface methods it doesn't implement
    var queue = std.ArrayListUnmanaged([]const u8).empty;
    defer queue.deinit(ctx.allocator);
    var walk: ?[]const u8 = class_name;
    while (walk) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        for (cls.interfaces.items) |iface| try queue.append(ctx.allocator, iface);
        walk = cls.parent;
    }
    var qi: usize = 0;
    while (qi < queue.items.len) : (qi += 1) {
        const iface_name = queue.items[qi];
        const iface = ctx.vm.interfaces.get(iface_name) orelse continue;
        for (iface.parents.items) |p| try queue.append(ctx.allocator, p);
        for (iface.methods.items) |method_name| {
            if (std.mem.indexOf(u8, method_name, "$hook_") != null or seen.contains(method_name)) continue;
            // a method the class has, in any case, isn't inherited abstract
            if (ctx.vm.hasMethod(class_name, method_name)) continue;
            try seen.put(ctx.allocator, method_name, {});
            const info = ClassDef.MethodInfo{ .name = method_name, .arity = 0, .visibility = .public, .is_abstract = true };
            if (filter) |f| if (!methodMatchesFilter(info, f)) continue;
            const declared = ctx.vm.declaredClassName(iface_name);
            try arr.append(ctx.allocator, .{ .object = try buildMethodObj(ctx, class_name, method_name, info, declared) });
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn methodMatchesFilter(info: ClassDef.MethodInfo, filter: i64) bool {
    return (methodModifiers(info) & filter) != 0;
}

fn methodModifiers(info: ClassDef.MethodInfo) i64 {
    var bits: i64 = 0;
    switch (info.visibility) {
        .public => bits |= 1,
        .protected => bits |= 2,
        .private => bits |= 4,
    }
    if (info.is_static) bits |= 16;
    if (info.is_final) bits |= 32;
    if (info.is_abstract) bits |= 64;
    return bits;
}

fn rcGetMethod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const method_name = try zpp.str(ctx, "ReflectionClass::getMethod", args, 0, "name");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (isInvokeName(method_name) and this.get("name") == .string and std.mem.eql(u8, this.get("name").string.bytes(), "Closure")) {
        const reflected = this.get("__object");
        const obj = try ctx.createObject("ReflectionMethod");
        try setClosureInvokeMethod(ctx, obj, if (reflected.closureName() != null) reflected else .null);
        return NativeResult.borrowed(.{ .object = obj });
    }
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    if (!ctx.vm.hasMethod(class_name, method_name)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Method {s}::{s}() does not exist", .{ class_name, method_name }) catch return error.OutOfMemory;
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }

    const declared = declaredMethodName(ctx.vm, class_name, method_name);
    const declaring = findDeclaringClass(ctx.vm, class_name, declared);
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.null);
    const info = cls.methods.get(declared) orelse ClassDef.MethodInfo{ .name = declared, .arity = 0 };
    const obj = try buildMethodObj(ctx, class_name, declared, info, declaring);
    return NativeResult.borrowed(.{ .object = obj });
}

// the spelling a method was declared with, found from a name in any case
fn declaredMethodName(vm: *VM, class_name: []const u8, method_name: []const u8) []const u8 {
    var walk: ?[]const u8 = class_name;
    while (walk) |cn| {
        const cls = vm.classes.getPtr(cn) orelse break;
        if (cls.methods.getKey(method_name)) |declared| return declared;
        walk = cls.parent;
    }
    return method_name;
}

fn rcHasMethod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const method_name = try zpp.str(ctx, "ReflectionClass::hasMethod", args, 0, "name");
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    // PHP method names are case-insensitive
    if (ctx.vm.hasMethod(class_name, method_name)) return NativeResult.scalar(.{ .bool = true });
    if (std.mem.eql(u8, class_name, "Closure") and isInvokeName(method_name)) return NativeResult.scalar(.{ .bool = true });
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            if (cls.methods.contains(method_name)) return NativeResult.scalar(.{ .bool = true });
            current = cls.parent;
        } else break;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcIsAbstract(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    // an interface is abstract when it has methods, its own or inherited
    const is_iface = this.get("__is_interface");
    if (is_iface == .bool and is_iface.bool) return NativeResult.scalar(.{ .bool = interfaceHasMethods(ctx.vm, class_name, 0) });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cls.is_abstract });
}

fn interfaceHasMethods(vm: *VM, name: []const u8, depth: usize) bool {
    if (depth > 64) return false;
    const idef = vm.interfaces.get(name) orelse return false;
    if (idef.methods.items.len > 0) return true;
    for (idef.parents.items) |parent| if (interfaceHasMethods(vm, parent, depth + 1)) return true;
    return false;
}

fn rcIsFinal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.is_enum) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = cls.is_final });
}

fn rcGetModifiers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // ReflectionClass::IS_EXPLICIT_ABSTRACT=64, IS_FINAL=32, IS_READONLY=65536;
    // an enum is implicitly final
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .int = 0 });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .int = 0 });
    var mods: i64 = 0;
    if (cls.is_abstract) mods |= 64;
    if (cls.is_final or cls.is_enum) mods |= 32;
    if (cls.is_readonly) mods |= 65536;
    return NativeResult.scalar(.{ .int = mods });
}

fn rcIsReadOnly(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cls.is_readonly });
}

fn rcIsCloneable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const is_iface = this.get("__is_interface");
    if (is_iface == .bool and is_iface.bool) return NativeResult.scalar(.{ .bool = false });
    const is_trait = this.get("__is_trait");
    if (is_trait == .bool and is_trait.bool) return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = true });
    if (cls.is_abstract) return NativeResult.scalar(.{ .bool = false });
    if (cls.is_enum) return NativeResult.scalar(.{ .bool = false });
    // an internal class without a clone handler, and its subclasses
    var walk: ?[]const u8 = class_name;
    while (walk) |n| {
        const c = ctx.vm.classes.get(n) orelse break;
        if (c.uncloneable) return NativeResult.scalar(.{ .bool = false });
        walk = c.parent;
    }
    if (cls.methods.get("__clone")) |m| {
        if (m.visibility != .public) return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn rcIsInterface(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const is_iface = this.get("__is_interface");
    return NativeResult.scalar(.{ .bool = is_iface == .bool and is_iface.bool });
}

fn rcIsAnonymous(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = this.get("name");
    if (name != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = class_names.isAnonymous(name.string.bytes()) });
}

// getInterfaces returns an array keyed by interface name with ReflectionClass
// instances as values. PHP behaviour: includes all interfaces from the class
// hierarchy plus their parents
fn rcGetInterfaces(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);
    var queue = std.ArrayListUnmanaged([]const u8).empty;
    defer queue.deinit(ctx.allocator);

    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        const cls = ctx.vm.classes.get(cn) orelse break;
        for (cls.interfaces.items) |iface| try queue.append(ctx.allocator, iface);
        current = cls.parent;
    }
    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const iface = queue.items[i];
        if (seen.contains(iface)) continue;
        try seen.put(ctx.allocator, iface, {});

        const refobj = try classObject(ctx, iface);
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(iface) }, .{ .object = refobj });

        if (ctx.vm.classes.get(iface)) |idef| {
            for (idef.interfaces.items) |sub| try queue.append(ctx.allocator, sub);
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// getTraits returns an array keyed by trait name with ReflectionClass instances
// as values, covering traits used by the class and its parent chain
fn rcGetTraits(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);

    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        const cls = ctx.vm.classes.get(cn) orelse break;
        for (cls.used_traits.items) |tname| {
            if (seen.contains(tname)) continue;
            try seen.put(ctx.allocator, tname, {});
            const refobj = try classObject(ctx, tname);
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(tname) }, .{ .object = refobj });
        }
        current = cls.parent;
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetInterfaceNames(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);
    var queue = std.ArrayListUnmanaged([]const u8).empty;
    defer queue.deinit(ctx.allocator);

    // PHP's order: parent class interfaces first, then own, with each interface
    // immediately followed by its transitively-extended parents
    // (IteratorAggregate -> Traversable). collect parent->child chain first
    var chain = std.ArrayListUnmanaged([]const u8).empty;
    defer chain.deinit(ctx.allocator);
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        try chain.append(ctx.allocator, cn);
        const cls = ctx.vm.classes.get(cn) orelse break;
        current = cls.parent;
    }
    var ci: usize = chain.items.len;
    while (ci > 0) {
        ci -= 1;
        const cls = ctx.vm.classes.get(chain.items[ci]) orelse continue;
        for (cls.interfaces.items) |iface| try emitInterfaceDeep(ctx, arr, &seen, iface);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn emitInterfaceDeep(ctx: *NativeContext, arr: *PhpArray, seen: *std.StringHashMapUnmanaged(void), name: []const u8) RuntimeError!void {
    if (seen.contains(name)) return;
    try seen.put(ctx.allocator, name, {});
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(name) });
    if (ctx.vm.interfaces.get(name)) |idef| {
        if (idef.parent) |p| try emitInterfaceDeep(ctx, arr, seen, p);
        for (idef.parents.items) |p| try emitInterfaceDeep(ctx, arr, seen, p);
    }
    if (ctx.vm.classes.get(name)) |idef| {
        for (idef.interfaces.items) |sub| try emitInterfaceDeep(ctx, arr, seen, sub);
    }
}

// scope: the class the arguments are evaluated in ("" for none)
fn buildReflectionAttribute(ctx: *NativeContext, attr: AttributeDef, target: i64, is_repeated: bool, scope: []const u8) RuntimeError!Value {
    const obj = try ctx.createObject("ReflectionAttribute");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(attr.name) });
    const args_arr = try ctx.createArray();
    for (attr.args, 0..) |stored_arg, i| {
        const arg = if (stored_arg == .array and !Value.isEmptyArrayDefault(stored_arg))
            Value{ .array = try ctx.vm.cloneArray(stored_arg.array) }
        else
            stored_arg;
        if (i < attr.arg_names.len) {
            if (attr.arg_names[i]) |arg_name| {
                try args_arr.set(ctx.allocator, .{ .string = Value.String.borrowed(arg_name) }, arg);
                continue;
            }
        }
        try args_arr.append(ctx.allocator, arg);
    }
    try obj.set(ctx.allocator, "__arguments", .{ .array = args_arr });
    try obj.set(ctx.allocator, "__target", .{ .int = target });
    try obj.set(ctx.allocator, "__is_repeated", .{ .bool = is_repeated });
    // the reflector the scope name came from may be gone by the time the
    // arguments are read
    try obj.set(ctx.allocator, "__scope", .{ .string = Value.String.borrowed(try ctx.createString(scope)) });
    return .{ .object = obj };
}

// IS_INSTANCEOF = 2 in PHP's ReflectionAttribute constants. When set, the
// filter matches any attribute whose class extends/implements the given name.
const REFLECTION_ATTRIBUTE_IS_INSTANCEOF: i64 = 2;

// php's reflect_attributes refuses an unknown filter flag, and with
// IS_INSTANCEOF a filter class that doesn't exist, before looking at any
// attribute
fn checkAttributeFilter(ctx: *NativeContext, args: []const Value, comptime owner: []const u8) RuntimeError!void {
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    if (flags & ~REFLECTION_ATTRIBUTE_IS_INSTANCEOF != 0) {
        try ctx.vm.setPendingException("ValueError", owner ++ "::getAttributes(): Argument #2 ($flags) must be a valid attribute filter flag");
        return error.RuntimeError;
    }
    if (flags & REFLECTION_ATTRIBUTE_IS_INSTANCEOF == 0 or args.len == 0 or args[0] != .string) return;
    const name = args[0].string.bytes();
    const bare = if (name.len > 0 and name[0] == '\\') name[1..] else name;
    if (ctx.vm.classes.contains(bare) or ctx.vm.interfaces.contains(bare) or ctx.vm.traits.contains(bare)) return;
    try ctx.vm.tryAutoload(bare);
    if (ctx.vm.pending_exception != null) return error.RuntimeError;
    if (ctx.vm.classes.contains(bare) or ctx.vm.interfaces.contains(bare) or ctx.vm.traits.contains(bare)) return;
    const msg = try std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" not found", .{bare});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("Error", msg);
    return error.RuntimeError;
}

fn buildAttributeArray(ctx: *NativeContext, attrs: []const AttributeDef, filter: ?[]const u8, target: i64, scope: []const u8) RuntimeError!NativeResult {
    return buildAttributeArrayWithFlags(ctx, attrs, filter, target, 0, scope);
}

fn buildAttributeArrayWithFlags(ctx: *NativeContext, attrs: []const AttributeDef, filter: ?[]const u8, target: i64, flags: i64, scope: []const u8) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (attrs) |attr| {
        if (filter) |f| {
            if (flags & REFLECTION_ATTRIBUTE_IS_INSTANCEOF != 0) {
                // ensure the attribute's class is loaded so isInstanceOf can
                // walk its parent chain. PHP-side `class_exists()` triggers
                // autoload implicitly; here we have to drive it ourselves
                if (!ctx.vm.classes.contains(attr.name)) {
                    try ctx.vm.tryAutoload(attr.name);
                }
                if (!ctx.vm.classes.contains(f)) {
                    try ctx.vm.tryAutoload(f);
                }
                if (!ctx.vm.isInstanceOf(attr.name, f)) continue;
            } else {
                if (!std.mem.eql(u8, attr.name, f)) continue;
            }
        }
        var count: usize = 0;
        for (attrs) |other| {
            if (std.mem.eql(u8, other.name, attr.name)) count += 1;
        }
        try arr.append(ctx.allocator, try buildReflectionAttribute(ctx, attr, target, count > 1, scope));
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const site = ctx.vm.declSite(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (site.doc_comment.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, site.doc_comment);
}

fn rmGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const func = rmLookupFunc(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.doc_comment.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, func.doc_comment);
}

fn rfGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = functionKey(this);
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(name_v.string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.doc_comment.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, func.doc_comment);
}

fn reflectionGetDocCommentFalse(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // zphp doesn't preserve doc comments through compilation (architectural)
    return NativeResult.scalar(.{ .bool = false });
}

fn rcGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try checkAttributeFilter(ctx, args, "ReflectionClass");
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, cls.attributes.items, filter, 1, flags, class_name);
}

fn rcGetProperties(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    try ctx.vm.resolveClassDefaults(class_name);
    // ?int $filter: null lists every property, otherwise those with any of
    // the given modifiers
    const filter: ?i64 = if (args.len >= 1 and args[0] != .null) try zpp.long(ctx, "ReflectionClass::getProperties", args, 0, "filter", true) else null;

    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);

    var is_own = true;
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        for (cls.properties.items) |prop| {
            if (!is_own and prop.visibility == .private) continue;
            if (!seen.contains(prop.name)) {
                try seen.put(ctx.allocator, prop.name, {});
                if (!matchPropFilter(filter, propertyFlags(prop, false))) continue;
                const obj = try buildPropertyObj(ctx, class_name, prop, name);
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        }
        var sp_iter = cls.static_props.iterator();
        while (sp_iter.next()) |entry| {
            const sp_name = entry.key_ptr.*;
            const vis: ClassDef.Visibility = cls.static_prop_visibility.get(sp_name) orelse .public;
            if (!is_own and vis == .private) continue;
            if (!seen.contains(sp_name)) {
                try seen.put(ctx.allocator, sp_name, {});
                const def = staticPropertyDef(&cls, sp_name, entry.value_ptr.*);
                if (!matchPropFilter(filter, propertyFlags(def, true))) continue;
                const obj = try buildPropertyObj(ctx, class_name, def, name);
                try obj.set(ctx.allocator, "__is_static", .{ .bool = true });
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        }
        if (ctx.vm.interfaces.contains(name)) {
            try appendInterfaceProperties(ctx, class_name, name, filter, arr, &seen);
        }
        current = cls.parent;
        is_own = false;
    }
    const reflected = this.get("__object");
    if (reflected == .object and (filter == null or filter.? & 1 != 0)) {
        var it = reflected.object.properties.iterator();
        while (it.next()) |entry| {
            const prop_name = entry.key_ptr.*;
            if (seen.contains(prop_name) or !hasDynamicProperty(ctx.vm, reflected.object, prop_name)) continue;
            const obj = try ctx.createObject("ReflectionProperty");
            try setPropertyReflection(ctx, obj, class_name, prop_name, null);
            try arr.append(ctx.allocator, .{ .object = obj });
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn appendInterfaceProperties(ctx: *NativeContext, reflected: []const u8, name: []const u8, filter: ?i64, arr: *PhpArray, seen: *std.StringHashMapUnmanaged(void)) RuntimeError!void {
    const iface = ctx.vm.interfaces.get(name) orelse return;
    for (iface.parents.items) |parent| {
        const cls = ctx.vm.classes.get(parent) orelse continue;
        for (cls.properties.items) |prop| {
            if (seen.contains(prop.name)) continue;
            try seen.put(ctx.allocator, prop.name, {});
            if (!matchPropFilter(filter, propertyFlags(prop, false))) continue;
            const obj = try buildPropertyObj(ctx, reflected, prop, parent);
            try arr.append(ctx.allocator, .{ .object = obj });
        }
        try appendInterfaceProperties(ctx, reflected, parent, filter, arr, seen);
    }
}

fn matchPropFilter(filter: ?i64, flags: i64) bool {
    const f = filter orelse return true;
    return flags & f != 0;
}

// a property's modifier bits as ReflectionProperty's IS_* constants name them
fn propertyFlags(prop: ClassDef.PropertyDef, is_static: bool) i64 {
    var flags: i64 = switch (prop.visibility) {
        .public => 1,
        .protected => 2,
        .private => 4,
    };
    if (is_static) flags |= 16;
    if (prop.is_final) flags |= 32;
    if (prop.is_readonly and !prop.readonly_undeclared) flags |= 128;
    if (prop.is_virtual) flags |= 512;
    return flags;
}

fn rcGetProperty(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = try zpp.str(ctx, "ReflectionClass::getProperty", args, 0, "name");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    try ctx.vm.resolveClassDefaults(class_name);

    if (visiblePropertyDef(ctx.vm, class_name, name)) |result| {
        const obj = try buildPropertyObjStatic(ctx, class_name, result.prop, result.declaring_class, result.is_static);
        return NativeResult.borrowed(.{ .object = obj });
    }
    const reflected = this.get("__object");
    if (reflected == .object and hasDynamicProperty(ctx.vm, reflected.object, name)) {
        const obj = try ctx.createObject("ReflectionProperty");
        try setPropertyReflection(ctx, obj, class_name, name, null);
        return NativeResult.borrowed(.{ .object = obj });
    }
    var shown_class = class_name;
    var shown_name = name;
    if (std.mem.indexOf(u8, name, "::")) |sep| {
        const qualifier = name[0..sep];
        shown_name = name[sep + 2 ..];
        const base = (try lookupClass(ctx, qualifier)) orelse {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" does not exist", .{qualifier});
            defer ctx.allocator.free(msg);
            return throwReflection(ctx, msg);
        };
        if (!ctx.vm.isInstanceOf(class_name, base)) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Fully qualified property name {s}::${s} does not specify a base class of {s}", .{ base, shown_name, class_name });
            defer ctx.allocator.free(msg);
            return throwReflection(ctx, msg);
        }
        shown_class = base;
        if (visiblePropertyDef(ctx.vm, base, shown_name)) |result| {
            const obj = try buildPropertyObjStatic(ctx, base, result.prop, result.declaring_class, result.is_static);
            return NativeResult.borrowed(.{ .object = obj });
        }
    }
    const msg = try std.fmt.allocPrint(ctx.allocator, "Property {s}::${s} does not exist", .{ shown_class, shown_name });
    defer ctx.allocator.free(msg);
    return throwReflection(ctx, msg);
}

fn rcHasProperty(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = try zpp.str(ctx, "ReflectionClass::hasProperty", args, 0, "name");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (visiblePropertyDef(ctx.vm, class_name, name) != null) return NativeResult.scalar(.{ .bool = true });
    const reflected = this.get("__object");
    if (reflected == .object) {
        // has_property with ZEND_PROPERTY_EXISTS, which never calls __isset
        if (hasDynamicProperty(ctx.vm, reflected.object, name)) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcNewLazyProxy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    ctx.vm.lazy_proxy_request = true;
    defer ctx.vm.lazy_proxy_request = false;
    const result = try rcNewLazyGhost(ctx, args);
    if (result.value == .object) result.value.object.lazy.?.proxy = true;
    return result;
}

// reflection_class_new_lazy and zend_object_make_lazy's refusals, before an
// object is made or reset lazy
fn lazyPreconditions(ctx: *NativeContext, class_name: []const u8, options_arg: ?Value, reset: ?*PhpObject, method: []const u8) RuntimeError!void {
    const options: i64 = if (options_arg) |o| (if (o == .int) o.int else 0) else 0;
    const arg_num: u8 = if (reset != null) 3 else 2;
    if (options & ~@as(i64, 8 | 16) != 0) return throwReflectionFmt(ctx, "ReflectionClass::{s}(): Argument #{d} ($options) contains invalid flags", .{ method, arg_num });
    if (reset == null and options & 16 != 0) return throwReflectionFmt(ctx, "ReflectionClass::{s}(): Argument #2 ($options) does not accept ReflectionClass::SKIP_DESTRUCTOR", .{method});
    // an initialized proxy may be reset; one being initialized is refused
    // below, as zend_object_make_lazy does. zphp's cycle collector runs at
    // other points than php's, so a destructor it runs may meet an object
    // php's would not have made lazy yet; that reset is let through
    if (reset) |obj| if (obj.lazy) |state| if (!ctx.vm.collecting_cycles) {
        if (state.initializer != .null and !state.running) return throwReflection(ctx, "Object is already lazy");
    };
    const def = ctx.vm.classes.get(class_name) orelse return;
    if (def.is_internal and !std.mem.eql(u8, def.name, "stdClass")) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot make instance of internal class lazy: {s} is internal", .{def.name});
        defer ctx.allocator.free(msg);
        _ = try ctx.vm.throwBuiltinException("Error", msg);
        return error.RuntimeError;
    }
    var parent = def.parent;
    while (parent) |pn| {
        const pdef = ctx.vm.classes.get(pn) orelse break;
        if (pdef.is_internal and !std.mem.eql(u8, pdef.name, "stdClass")) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot make instance of internal class lazy: {s} inherits internal class {s}", .{ def.name, pdef.name });
            defer ctx.allocator.free(msg);
            _ = try ctx.vm.throwBuiltinException("Error", msg);
            return error.RuntimeError;
        }
        parent = pdef.parent;
    }
    if (reset) |obj| {
        if (obj.lazy) |state| if (state.running) {
            _ = try ctx.vm.throwBuiltinException("Error", "Can not reset an object while it is being initialized");
            return error.RuntimeError;
        };
    }
}

fn rcNewLazyGhost(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try lazyPreconditions(ctx, class_name, if (args.len > 1) args[1] else null, null, if (ctx.vm.lazy_proxy_request) "newLazyProxy" else "newLazyGhost");
    // the lazy object owns its initializer until it runs or is cleared
    VM.retainValue(args[0]);
    const obj = try ctx.vm.allocObject(.{ .class_name = try ctx.vm.stableClassName(class_name) });
    try ctx.vm.initObjectProperties(obj, class_name);
    const state = try ctx.allocator.create(PhpObject.LazyState);
    const count = if (obj.slots) |slots| slots.len else 0;
    state.* = .{ .initializer = args[0], .pending = try ctx.allocator.alloc(bool, count), .skip_serialize = args.len > 1 and args[1] == .int and (args[1].int & 8) != 0 };
    @memset(state.pending, true);
    obj.lazy = state;
    if (count == 0) {
        ctx.vm.releaseValue(state.initializer);
        state.initializer = .null;
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn rcInitializeLazyObject(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const obj = args[0].object;
    try ctx.vm.triggerLazyInit(obj);
    return NativeResult.borrowed(.{ .object = obj.storage() });
}

fn rcIsUninitializedLazyObject(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const state = args[0].object.lazy orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = state.initializer != .null and !state.running });
}

fn rcMarkLazyObjectAsInitialized(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    if (args[0].object.lazy) |state| {
        if (!state.running) {
            const initializer = state.initializer;
            state.initializer = .null;
            ctx.vm.releaseValue(initializer);
        }
    }
    return NativeResult.borrowed(.{ .object = args[0].object.storage() });
}

fn rcNewInstanceWithoutConstructor(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    // internal final classes whose objects only their own code creates
    for ([_][]const u8{ "Closure", "Generator", "Fiber", "WeakReference", "WeakMap", "InternalIterator", "Random\\Randomizer", "CurlHandle", "CurlMultiHandle", "CurlShareHandle" }) |refused| {
        if (std.ascii.eqlIgnoreCase(class_name, refused)) return throwReflectionFmt(ctx, "Class {s} is an internal class marked as final that cannot be instantiated without invoking its constructor", .{class_name});
    }
    try checkInstantiable(ctx, class_name);

    const obj = try ctx.vm.allocObject(.{ .class_name = try ctx.vm.stableClassName(class_name) });

    // mirror the `new` path: install slot layout + per-instance default copies
    // (initObjectProperties deep-clones array/object defaults via copyDefault, so
    // typed-array defaults like `public array $attr = []` aren't shared templates
    // and aren't left null). the previous hand-rolled loop skipped the slot layout
    // and stored the raw shared default, leaving non-scalar defaults wrong
    try ctx.vm.initObjectProperties(obj, class_name);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rcGetShortName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (std.mem.lastIndexOfScalar(u8, name, '\\')) |pos| {
        return try NativeResult.copyString(ctx.allocator, name[pos + 1 ..]);
    }
    return NativeResult.shareString(this.get("name").string);
}

fn rcGetNamespaceName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.literal("");
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.literal("");
    if (std.mem.lastIndexOfScalar(u8, name, '\\')) |pos| {
        return try NativeResult.copyString(ctx.allocator, name[0..pos]);
    }
    return NativeResult.literal("");
}

fn rcInNamespace(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = std.mem.indexOfScalar(u8, name, '\\') != null });
}

fn rcIsTrait(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = this.get("__is_trait");
    return NativeResult.scalar(.{ .bool = v == .bool and v.bool });
}

fn rcGetTraitNames(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    const arr = try ctx.createArray();
    for (cls.used_traits.items) |name| {
        try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(name) });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcIsEnum(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cls.is_enum });
}

pub const VisibleConstant = struct { declaring: []const u8, name: []const u8, value: Value };

// what a class can see as its constants, in php's order: its own (trait
// constants included) in declaration order, then its parents', then its
// interfaces'. an override hides the inherited one and a parent's private
// constant is not inherited
pub fn visibleConstants(ctx: *NativeContext, class_name: []const u8, out: *std.ArrayListUnmanaged(VisibleConstant)) RuntimeError!void {
    var chain: std.ArrayListUnmanaged([]const u8) = .empty;
    defer chain.deinit(ctx.allocator);
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        try chain.append(ctx.allocator, name);
        current = cls.parent;
    }
    for (chain.items, 0..) |name, depth| try appendOwnConstants(ctx, name, depth == 0, out);
    for (chain.items) |name| try appendInterfaceConstants(ctx, name, out, 0);
}

fn appendOwnConstants(ctx: *NativeContext, name: []const u8, is_own: bool, out: *std.ArrayListUnmanaged(VisibleConstant)) RuntimeError!void {
    const cls = ctx.vm.classes.get(name) orelse return;
    for (cls.constant_order.items) |cname| try appendConstant(ctx, cls, name, cname, is_own, out);
    var it = cls.constants.keyIterator();
    while (it.next()) |cname| try appendConstant(ctx, cls, name, cname.*, is_own, out);
}

fn appendInterfaceConstants(ctx: *NativeContext, name: []const u8, out: *std.ArrayListUnmanaged(VisibleConstant), depth: usize) RuntimeError!void {
    if (depth > 64) return;
    const cls = ctx.vm.classes.get(name) orelse return;
    for (cls.interfaces.items) |iface| {
        try appendOwnConstants(ctx, iface, false, out);
        try appendInterfaceConstants(ctx, iface, out, depth + 1);
    }
}

fn appendConstant(ctx: *NativeContext, cls: ClassDef, declaring: []const u8, cname: []const u8, is_own: bool, out: *std.ArrayListUnmanaged(VisibleConstant)) RuntimeError!void {
    const stored = cls.constants.get(cname) orelse return;
    // an interface's constant still waiting for its expression
    const value = if (stored == .undef) try ctx.vm.evaluateClassConstant(declaring, cname) else ctx.vm.enumCase(stored);
    if (!is_own and (cls.const_visibility.get(cname) orelse .public) == .private) return;
    for (out.items) |seen| if (std.mem.eql(u8, seen.name, cname)) return;
    try out.append(ctx.allocator, .{ .declaring = declaring, .name = cname, .value = value });
}

// a class constant's modifier bits as ReflectionClassConstant names them
fn constantFlags(vm: *VM, declaring: []const u8, name: []const u8) i64 {
    const cls = vm.classes.get(declaring) orelse return 1;
    var flags: i64 = switch (cls.const_visibility.get(name) orelse .public) {
        .public => 1,
        .protected => 2,
        .private => 4,
    };
    if (cls.const_final.contains(name)) flags |= 32;
    return flags;
}

fn constantFilter(ctx: *NativeContext, args: []const Value, label: []const u8) RuntimeError!?i64 {
    if (args.len == 0 or args[0] == .null) return null;
    return try zpp.long(ctx, label, args, 0, "filter", true);
}

fn rcGetConstants(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const filter = try constantFilter(ctx, args, "ReflectionClass::getConstants");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    // php evaluates the class's constant expressions first
    try ctx.vm.updateClassConstants(class_name);
    var constants: std.ArrayListUnmanaged(VisibleConstant) = .empty;
    defer constants.deinit(ctx.allocator);
    try visibleConstants(ctx, class_name, &constants);
    const arr = try ctx.createArray();
    for (constants.items) |c| {
        if (!matchPropFilter(filter, constantFlags(ctx.vm, c.declaring, c.name))) continue;
        try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(c.name) }, c.value);
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetReflectionConstants(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const filter = try constantFilter(ctx, args, "ReflectionClass::getReflectionConstants");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    // php evaluates the class's constant expressions first
    try ctx.vm.updateClassConstants(class_name);
    var constants: std.ArrayListUnmanaged(VisibleConstant) = .empty;
    defer constants.deinit(ctx.allocator);
    try visibleConstants(ctx, class_name, &constants);
    const arr = try ctx.createArray();
    for (constants.items) |c| {
        if (!matchPropFilter(filter, constantFlags(ctx.vm, c.declaring, c.name))) continue;
        try arr.append(ctx.allocator, try buildReflectionClassConstant(ctx, c.declaring, c.name, c.value));
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetReflectionConstant(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    // php evaluates the class's constant expressions first
    try ctx.vm.updateClassConstants(class_name);
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const target = args[0].string.bytes();

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constants.contains(target)) {
            if (cls.constants.get(target)) |val| {
                return NativeResult.borrowed(try buildReflectionClassConstant(ctx, name, target, ctx.vm.enumCase(val)));
            }
        }
        current = cls.parent;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcHasConstant(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const target = try zpp.str(ctx, "ReflectionClass::hasConstant", args, 0, "name");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = findConstantOwner(ctx, class_name, target, 0) != null });
}

fn rcGetConstant(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const target = try zpp.str(ctx, "ReflectionClass::getConstant", args, 0, "name");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    // php evaluates the class's constant expressions first
    try ctx.vm.updateClassConstants(class_name);
    if (findConstantOwner(ctx, class_name, target, 0) != null) {
        if (ctx.vm.getClassConstant(class_name, target)) |val| return NativeResult.share(ctx.vm.enumCase(val));
    }
    try ctx.vm.raiseError(VM.E_DEPRECATED, "ReflectionClass::getConstant() for a non-existent constant is deprecated, use ReflectionClass::hasConstant() to check if the constant exists");
    return NativeResult.scalar(.{ .bool = false });
}

fn buildReflectionClassConstant(ctx: *NativeContext, class_name: []const u8, const_name: []const u8, _: Value) RuntimeError!Value {
    // PHP's ReflectionClassConstant only exposes 'name' and 'class' as public
    // properties; the value is looked up from the class table on demand. zphp
    // previously stored a third public '_value' which polluted print_r/iter
    const obj = try ctx.createObject("ReflectionClassConstant");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(const_name) });
    try obj.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(class_name) });
    return .{ .object = obj };
}

fn rccGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    // $name is a typed property; unset, reading it is php's error
    if (this.isUnset("name") or this.get("name") != .string) return raiseError(ctx, "Error", "Typed property ReflectionClassConstant::$name must not be accessed before initialization", .{});
    return NativeResult.share(this.get("name"));
}

fn rccGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = this.get("class");
    const const_name = this.get("name");
    if (class_name != .string or const_name != .string) return NativeResult.scalar(.{ .bool = false });
    const doc = findConstantDoc(ctx, class_name.string.bytes(), const_name.string.bytes(), 0) orelse return NativeResult.scalar(.{ .bool = false });
    if (doc.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, doc);
}

pub fn findConstantOwner(ctx: *NativeContext, class_name: []const u8, name: []const u8, depth: usize) ?[]const u8 {
    if (depth >= 256) return null;
    if (ctx.vm.trait_constants.getEntry(class_name)) |entry| {
        for (entry.value_ptr.*) |constant| {
            if (std.mem.eql(u8, constant.name, name)) return entry.key_ptr.*;
        }
    }
    if (ctx.vm.classes.getEntry(class_name)) |entry| {
        const cls = entry.value_ptr;
        if (cls.constants.contains(name)) return entry.key_ptr.*;
        if (cls.parent) |parent| {
            if (findConstantOwner(ctx, parent, name, depth + 1)) |owner| return owner;
        }
        for (cls.interfaces.items) |interface| {
            if (findConstantOwner(ctx, interface, name, depth + 1)) |owner| return owner;
        }
    }
    return null;
}

pub fn findConstantDoc(ctx: *NativeContext, class_name: []const u8, name: []const u8, depth: usize) ?[]const u8 {
    const owner = findConstantOwner(ctx, class_name, name, depth) orelse return null;
    if (ctx.vm.classes.get(owner)) |cls| return cls.constant_docs.get(name) orelse "";
    if (ctx.vm.trait_constants.get(owner)) |constants| {
        for (constants) |constant| {
            if (std.mem.eql(u8, constant.name, name)) return constant.doc_comment;
        }
    }
    return null;
}

fn rccGetValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.null);
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constants.get(const_name)) |val| {
            if (val == .undef) return NativeResult.share(try ctx.vm.evaluateClassConstant(name, const_name));
            return NativeResult.share(ctx.vm.enumCase(val));
        }
        current = cls.parent;
    }
    return NativeResult.scalar(.null);
}

fn rccGetModifiers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP returns a bitmask: ReflectionClassConstant::IS_PUBLIC=1,
    // IS_PROTECTED=2, IS_PRIVATE=4, plus IS_FINAL=32 when declared `final`
    var mods: i64 = 0;
    if (rccVisibility(ctx)) |v| {
        mods |= switch (v) {
            .public => 1,
            .protected => 2,
            .private => 4,
        };
    } else mods |= 1;
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = mods });
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.{ .int = mods });
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .int = mods });
    if (ctx.vm.classes.get(class_name)) |cls| {
        if (cls.const_final.contains(const_name)) mods |= 32;
    }
    return NativeResult.scalar(.{ .int = mods });
}

fn rccGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.null);
    const rc = try classObject(ctx, class_name);
    return NativeResult.borrowed(.{ .object = rc });
}

fn rccConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    _ = try bindClassConstant(ctx, args);
    return NativeResult.scalar(.null);
}

fn bindClassConstant(ctx: *NativeContext, args: []const Value) RuntimeError![]const u8 {
    const this = getThis(ctx) orelse return throwReflection(ctx, "ReflectionClassConstant::__construct called without an object");
    const label = if (ctx.vm.isInstanceOf(this.class_name, "ReflectionEnumBackedCase"))
        "ReflectionEnumBackedCase::__construct"
    else if (ctx.vm.isInstanceOf(this.class_name, "ReflectionEnumUnitCase"))
        "ReflectionEnumUnitCase::__construct"
    else
        "ReflectionClassConstant::__construct";
    const class_arg = try zpp.objOrStr(ctx, label, args, 0, "class");
    const const_name = try zpp.str(ctx, label, args, 1, "constant");
    const class_name = try classArgument(ctx, class_arg);
    const owner = findConstantOwner(ctx, class_name, const_name, 0) orelse {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Constant {s}::{s} does not exist", .{ class_name, const_name });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    };
    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(try ctx.vm.internName(const_name)) });
    try this.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(owner) });
    return owner;
}

fn rccGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try checkAttributeFilter(ctx, args, "ReflectionClassConstant");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.null);
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const cls = ctx.vm.classes.get(class_name) orelse {
        return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    };
    if (cls.constant_attributes.get(const_name)) |attrs| {
        return try buildAttributeArray(ctx, attrs, null, 16, class_name);
    }
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

fn rccVisibility(ctx: *NativeContext) ?@import("../runtime/vm.zig").ClassDef.Visibility {
    const this = getThis(ctx) orelse return null;
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return null;
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return null;
    const cls = ctx.vm.classes.get(class_name) orelse return null;
    return cls.const_visibility.get(const_name);
}

fn rccIsPublic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const v = rccVisibility(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = v == .public });
}

fn rccIsProtected(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const v = rccVisibility(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = v == .protected });
}

fn rccIsPrivate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const v = rccVisibility(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = v == .private });
}

fn rccIsFinal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cls.const_final.contains(const_name) });
}

fn rccIsEnumCase(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    if (!cls.is_enum) return NativeResult.scalar(.{ .bool = false });
    for (cls.case_order.items) |case_name| {
        if (std.mem.eql(u8, case_name, const_name)) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rccGetType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.null);
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            if (cls.constant_types.get(const_name)) |type_str| {
                if (cls.constants.contains(const_name)) {
                    return NativeResult.borrowed(.{ .object = try createTypeObj(ctx, type_str, false, cn) });
                }
            }
            current = cls.parent;
        } else break;
    }
    return NativeResult.scalar(.null);
}

fn rccHasType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            if (cls.constant_types.get(const_name) != null) return NativeResult.scalar(.{ .bool = true });
            current = cls.parent;
        } else break;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcIsInternal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = isInternalClassName(ctx.vm, name_v.string.bytes()) });
}

fn rcIsUserDefined(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = !isInternalClassName(ctx.vm, name_v.string.bytes()) });
}

// a class, interface or trait the runtime declared rather than a script
pub fn isInternalClassName(vm: *VM, name: []const u8) bool {
    if (vm.classes.get(name)) |def| return def.is_internal;
    if (vm.interfaces.contains(name)) return vm.builtin_interfaces.contains(vm.declaredClassName(name));
    return false;
}

fn rcGetFileName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const site = ctx.vm.declSite(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (site.file.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, site.file);
}

fn rcGetStartLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const site = ctx.vm.declSite(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (site.start_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(site.start_line) });
}

fn rcGetEndLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const site = ctx.vm.declSite(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (site.end_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(site.end_line) });
}

fn rcGetDefaultProperties(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    try ctx.vm.resolveClassDefaults(class_name);
    // php's add_class_vars: the static properties (their current values)
    // first, then the instance properties' defaults
    const statics = (try rcGetStaticProperties(ctx, &.{})).value;
    const arr = if (statics == .array) statics.array else try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);
    var is_own = true;
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        for (cls.properties.items) |prop| {
            if (!is_own and prop.visibility == .private) continue;
            if (seen.contains(prop.name)) continue;
            try seen.put(ctx.allocator, prop.name, {});
            // a typed property without a default has none to list
            if (!cls.is_internal and prop.type_str.len > 0 and (!prop.has_default or prop.is_promoted)) continue;
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(prop.name) }, prop.default);
        }
        current = cls.parent;
        is_own = false;
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetStaticProperties(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    try ctx.vm.resolveClassDefaults(class_name);
    const arr = try ctx.createArray();
    var current: ?[]const u8 = class_name;
    var is_own = true;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        var it = cls.static_props.iterator();
        while (it.next()) |entry| {
            // a redeclared static hides the ancestor's, and an ancestor's
            // private one isn't the class's
            const key: PhpArray.Key = .{ .string = Value.String.borrowed(entry.key_ptr.*) };
            if (arr.contains(key)) continue;
            if (entry.value_ptr.* == .undef) continue;
            if (!is_own and (cls.static_prop_visibility.get(entry.key_ptr.*) orelse .public) == .private) continue;
            try arr.set(ctx.allocator, key, entry.value_ptr.*);
        }
        current = cls.parent;
        is_own = false;
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetStaticPropertyValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const prop_name = try zpp.str(ctx, "ReflectionClass::getStaticPropertyValue", args, 0, "name");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    try ctx.vm.resolveClassDefaults(class_name);
    const found = visiblePropertyDef(ctx.vm, class_name, prop_name);
    if (found != null and found.?.is_static) {
        const v = (try staticPropertyRaw(ctx, class_name, prop_name)) orelse .undef;
        if (v != .undef) return NativeResult.share(v);
        if (args.len >= 2) return NativeResult.share(args[1]);
        const msg = try std.fmt.allocPrint(ctx.allocator, "Typed property {s}::${s} must not be accessed before initialization", .{ class_name, prop_name });
        defer ctx.allocator.free(msg);
        _ = try ctx.vm.throwBuiltinException("Error", msg);
        return error.RuntimeError;
    }
    if (args.len >= 2) return NativeResult.share(args[1]);
    const msg = try std.fmt.allocPrint(ctx.allocator, "Property {s}::${s} does not exist", .{ class_name, prop_name });
    defer ctx.allocator.free(msg);
    return throwReflection(ctx, msg);
}

fn rcSetStaticPropertyValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const prop_name = try zpp.str(ctx, "ReflectionClass::setStaticPropertyValue", args, 0, "name");
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    try ctx.vm.resolveClassDefaults(class_name);
    const found = visiblePropertyDef(ctx.vm, class_name, prop_name);
    if (found == null or !found.?.is_static) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Class {s} does not have a property named {s}", .{ class_name, prop_name });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    var value = args[1];
    if (try ctx.vm.checkPropertyType(&value, found.?.prop.type_str, found.?.declaring_class, prop_name)) return error.RuntimeError;
    try ctx.vm.setStaticPropValue(class_name, prop_name, value);
    return NativeResult.scalar(.null);
}

// ReflectionMethod::createFromMethodName('Class::method'), an instance of the
// class it was called on
fn rmCreateFromMethodName(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const method = try zpp.str(ctx, "ReflectionMethod::createFromMethodName", args, 0, "method");
    const class_name = ctx.vm.currentFrame().called_class orelse "ReflectionMethod";
    if (ctx.vm.classes.get(class_name)) |cls| if (cls.is_abstract) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot instantiate abstract class {s}", .{class_name});
        defer ctx.allocator.free(msg);
        _ = try ctx.vm.throwBuiltinException("Error", msg);
        return error.RuntimeError;
    };
    const obj = try ctx.createObject(class_name);
    errdefer ctx.vm.releaseValue(.{ .object = obj });
    _ = try initMethodReflection(ctx, obj, &.{.{ .string = Value.String.borrowed(method) }}, false);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rmConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return initMethodReflection(ctx, this, args, true);
}

// php's instantiate_reflection_method
fn initMethodReflection(ctx: *NativeContext, this: *PhpObject, args: []const Value, is_constructor: bool) RuntimeError!NativeResult {
    const label = if (is_constructor) "ReflectionMethod::__construct" else "ReflectionMethod::createFromMethodName";
    const first_param = if (is_constructor) "objectOrMethod" else "method";
    if (is_constructor and args.len == 1) {
        try ctx.vm.raiseError(VM.E_DEPRECATED, "Calling ReflectionMethod::__construct() with 1 argument is deprecated, use ReflectionMethod::createFromMethodName() instead");
    }
    const arg1 = try zpp.objOrStr(ctx, label, args, 0, first_param);
    const arg2 = if (is_constructor) try zpp.strOrNull(ctx, label, args, 1, "method") else null;

    var class_name: []const u8 = undefined;
    var method_name: []const u8 = undefined;
    var class_text: ?[]const u8 = null;
    const arg1_object = arg1 == .object or isClosureValue(arg1);
    if (arg1_object) {
        method_name = arg2 orelse {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #2 ($method) cannot be null when argument #1 ($objectOrMethod) is an object", .{label});
            defer ctx.allocator.free(msg);
            _ = try ctx.vm.throwBuiltinException("ValueError", msg);
            return error.RuntimeError;
        };
        class_name = try classArgument(ctx, arg1);
    } else if (arg2) |m| {
        class_text = arg1.string.bytes();
        method_name = m;
    } else {
        const text = arg1.string.bytes();
        const sep = std.mem.indexOf(u8, text, "::") orelse {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #1 (${s}) must be a valid method name", .{ label, first_param });
            defer ctx.allocator.free(msg);
            return throwReflection(ctx, msg);
        };
        class_text = text[0..sep];
        method_name = text[sep + 2 ..];
    }
    if (class_text) |text| class_name = try classArgument(ctx, .{ .string = Value.String.borrowed(text) });
    if (arg1.closureName() != null and isInvokeName(method_name)) {
        try setClosureInvokeMethod(ctx, this, arg1);
        return NativeResult.scalar(.null);
    }

    if (!ctx.vm.hasMethod(class_name, method_name) and
        !hasInterfaceMethod(ctx.vm, class_name, method_name) and
        !hasAbstractMethodInChain(ctx.vm, class_name, method_name))
    {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Method {s}::{s}() does not exist", .{ class_name, method_name });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    // report the declared spellings of a class and method named in any case
    method_name = declaredMethodName(ctx.vm, class_name, method_name);
    const declaring = findDeclaringClass(ctx.vm, class_name, method_name);
    const info = blk: {
        if (ctx.vm.classes.get(declaring)) |cls| {
            break :blk cls.methods.get(method_name) orelse ClassDef.MethodInfo{ .name = method_name, .arity = 0 };
        } else if (ctx.vm.classes.get(class_name)) |cls| {
            break :blk cls.methods.get(method_name) orelse ClassDef.MethodInfo{ .name = method_name, .arity = 0 };
        } else {
            break :blk ClassDef.MethodInfo{ .name = method_name, .arity = 0 };
        }
    };

    // the names may be slices of an argument string that dies with the call
    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(try ctx.vm.internName(method_name)) });
    try this.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(try ctx.vm.internName(declaring)) });
    try this.set(ctx.allocator, "__class", .{ .string = Value.String.borrowed(try ctx.vm.internName(class_name)) });
    try this.set(ctx.allocator, "__declaring_class", .{ .string = Value.String.borrowed(try ctx.vm.internName(declaring)) });
    try this.set(ctx.allocator, "__is_static", .{ .bool = info.is_static });
    try this.set(ctx.allocator, "__visibility", .{ .int = @backingInt(info.visibility) });

    var buf: [256]u8 = undefined;
    const key = class_names.memberKey(&buf, declaring, method_name);
    if (ctx.vm.functions.get(key)) |func| {
        try this.set(ctx.allocator, "__arity", .{ .int = func.arity });
        try this.set(ctx.allocator, "__required_params", .{ .int = func.required_params });
    } else if (native_params.get(key)) |sig| {
        try this.set(ctx.allocator, "__arity", .{ .int = @intCast(sig.params.len) });
        try this.set(ctx.allocator, "__required_params", .{ .int = @intCast(nativeRequiredCount(sig)) });
    } else {
        try this.set(ctx.allocator, "__arity", .{ .int = info.arity });
        try this.set(ctx.allocator, "__required_params", .{ .int = info.arity });
    }

    return NativeResult.scalar(.null);
}

// the key a method's function is filed under: "Class::method", or for a
// closure's __invoke the closure itself
pub fn methodKey(this: *PhpObject, buf: []u8, declaring: []const u8, method_name: []const u8) []const u8 {
    if (this.get("__closure").closureName()) |instance| return instance;
    return class_names.memberKey(buf, declaring, method_name);
}

// a ReflectionMethod of a closure's __invoke: php's
// zend_get_closure_invoke_method, which reflects the closure's own signature
// closure is .null for the class's own __invoke, which reflects an empty
// closure; invoking it runs the closure it is given
fn setClosureInvokeMethod(ctx: *NativeContext, obj: *PhpObject, closure: Value) RuntimeError!void {
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed("__invoke") });
    try obj.set(ctx.allocator, "class", .{ .string = Value.String.borrowed("Closure") });
    try obj.set(ctx.allocator, "__class", .{ .string = Value.String.borrowed("Closure") });
    try obj.set(ctx.allocator, "__declaring_class", .{ .string = Value.String.borrowed("Closure") });
    try obj.set(ctx.allocator, "__is_static", .{ .bool = false });
    try obj.set(ctx.allocator, "__visibility", .{ .int = @backingInt(ClassDef.Visibility.public) });
    try obj.set(ctx.allocator, "__closure", if (closure == .null) .{ .bool = true } else closure);
    const key = closure.closureName() orelse "";
    if (ctx.vm.functions.get(key)) |func| {
        try obj.set(ctx.allocator, "__arity", .{ .int = func.arity });
        try obj.set(ctx.allocator, "__required_params", .{ .int = func.required_params });
    } else {
        try obj.set(ctx.allocator, "__arity", .{ .int = 0 });
        try obj.set(ctx.allocator, "__required_params", .{ .int = 0 });
    }
}

fn isInvokeName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "__invoke");
}

// the method a method implements or overrides (php's common.prototype)
fn methodPrototype(ctx: *NativeContext, this: *PhpObject) ?[]const u8 {
    if (this.get("__closure") != .null) return null;
    const name = methodLookupName(this) orelse return null;
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return null;
    return @import("reflection_string.zig").prototypeOf(ctx.vm, declaring, name, 0);
}

fn rmGetPrototype(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    const proto = methodPrototype(ctx, this) orelse {
        const ce = reflectedClass(this) orelse "";
        return throwReflectionFmt(ctx, "Method {s}::{s} does not have a prototype", .{ ce, name });
    };
    const obj = try ctx.createObject("ReflectionMethod");
    var buf: [256]u8 = undefined;
    const full = try ctx.vm.internName(class_names.memberKey(&buf, proto, name));
    _ = try initMethodReflection(ctx, obj, &.{.{ .string = Value.String.borrowed(full) }}, false);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rmHasPrototype(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = methodPrototype(ctx, this) != null });
}

fn rmGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rmLookupFunc(ctx: *NativeContext) ?@TypeOf(ctx.vm.functions.get("").?) {
    const this = getThis(ctx) orelse return null;
    const method_name = methodLookupName(this) orelse return null;
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return null;
    var buf: [256]u8 = undefined;
    const key = methodKey(this, &buf, declaring, method_name);
    return ctx.vm.functions.get(key);
}

fn rmGetFileName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const func = rmLookupFunc(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.file_path.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, func.file_path);
}

fn rmGetStartLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const func = rmLookupFunc(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.start_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(func.start_line) });
}

fn rmGetEndLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const func = rmLookupFunc(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.end_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(func.end_line) });
}

fn rmIsInternal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const dc = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = isInternalClassName(ctx.vm, dc) });
}

fn rmIsUserDefined(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const dc = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = !isInternalClassName(ctx.vm, dc) });
}

fn reflectionEmptyString(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal("");
}

fn rmGetParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.null);

    var buf: [256]u8 = undefined;
    const key = methodKey(this, &buf, declaring, method_name);
    const func = ctx.vm.functions.get(key) orelse {
        if (native_params.get(key)) |sig| return NativeResult.borrowed(try buildNativeParamArray(ctx, sig, key));
        return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    };

    const result = try buildParamArray(ctx, func, key);
    if (this.get("__closure").closureName() != null and result == .array) {
        for (result.array.entries.items) |entry| if (entry.value == .object) {
            try entry.value.object.set(ctx.allocator, "__closure", this.get("__closure"));
            try entry.value.object.set(ctx.allocator, "__closure_method", .{ .bool = true });
        };
    }
    if (this.get("__hook_method") == .string and result == .array) {
        for (result.array.entries.items) |entry| {
            if (entry.value == .object) try entry.value.object.set(ctx.allocator, "__hook_declaring_function", .{ .object = this });
        }
    }
    return NativeResult.borrowed(result);
}

fn rmIsPublic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("__visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 0 });
}

fn rmIsProtected(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("__visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 1 });
}

fn rmIsPrivate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("__visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 2 });
}

fn rmIsStatic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const is_static = this.get("__is_static");
    return NativeResult.scalar(.{ .bool = is_static == .bool and is_static.bool });
}

fn rmGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.null);

    const obj = try classObject(ctx, declaring);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rmGetReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const hook_type = this.get("__hook_return_type");
    if (hook_type == .string) {
        if (hook_type.string.bytes().len == 0) return NativeResult.scalar(.null);
        return NativeResult.borrowed(.{ .object = try createTypeObj(ctx, hook_type.string.bytes(), false, this.get("__declaring_class").string.bytes()) });
    }
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.null);

    var buf: [256]u8 = undefined;
    const key = methodKey(this, &buf, declaring, method_name);
    const return_type = if (methodTypeInfo(ctx.vm, key)) |ti| ti.return_type else nativeReturnType(ctx, key);
    if (return_type.len == 0) return NativeResult.scalar(.null);

    const obj = try createTypeObj(ctx, return_type, false, declaring);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rmHasReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const hook_type = this.get("__hook_return_type");
    if (hook_type == .string) {
        return NativeResult.scalar(.{ .bool = hook_type.string.bytes().len > 0 });
    }
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .bool = false });
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });

    var buf: [256]u8 = undefined;
    const key = methodKey(this, &buf, declaring, method_name);
    const return_type = if (methodTypeInfo(ctx.vm, key)) |ti| ti.return_type else nativeReturnType(ctx, key);
    return NativeResult.scalar(.{ .bool = return_type.len > 0 });
}

// a method's declared types; one a class took from a trait is filed under
// the trait's method
pub fn methodTypeInfo(vm: *VM, key: []const u8) ?vm_mod.TypeInfo {
    if (vm_mod.getTypeInfo(key)) |ti| return ti;
    const func = vm.functions.get(key) orelse return null;
    return vm_mod.getTypeInfo(func.name);
}

// php 8.1+ internal methods declare tentative return types that a user
// override may still differ from; user methods never have one
fn methodTentativeReturnType(ctx: *NativeContext, this: *PhpObject) []const u8 {
    const method_name = methodLookupName(this) orelse return "";
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return "";
    var buf: [256]u8 = undefined;
    const key = methodKey(this, &buf, declaring, method_name);
    if (ctx.vm.functions.contains(key)) return "";
    const sig = native_params.get(key) orelse return "";
    return sig.tentative_returns;
}

fn rmHasTentativeReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = methodTentativeReturnType(ctx, this).len > 0 });
}

fn rmGetTentativeReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const tentative = methodTentativeReturnType(ctx, this);
    if (tentative.len == 0) return NativeResult.scalar(.null);
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else null;
    return NativeResult.borrowed(.{ .object = try createTypeObj(ctx, tentative, false, declaring) });
}

fn rmIsConstructor(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = this.get("name");
    return NativeResult.scalar(.{ .bool = name == .string and std.mem.eql(u8, name.string.bytes(), "__construct") });
}

fn rmIsDestructor(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = this.get("name");
    return NativeResult.scalar(.{ .bool = name == .string and std.mem.eql(u8, name.string.bytes(), "__destruct") });
}

fn rmGetNumberOfParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const arity = this.get("__arity");
    return if (arity == .int) NativeResult.share(arity) else NativeResult.scalar(.{ .int = 0 });
}

fn rmGetNumberOfRequiredParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const req = this.get("__required_params");
    return if (req == .int) NativeResult.share(req) else NativeResult.scalar(.{ .int = 0 });
}

fn rpGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rpGetType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const type_val = this.get("__type_name");
    if (type_val != .string or type_val.string.bytes().len == 0) return NativeResult.scalar(.null);

    const nullable = this.get("__nullable");
    var is_nullable = nullable == .bool and nullable.bool;
    // PHP's implicit-nullable: `foo($x = null)` reports the type as nullable
    // even though source didn't write '?'. detect by checking default == null
    const has_default = this.get("__has_default");
    if (!is_nullable and has_default == .bool and has_default.bool) {
        if (this.get("__default_value") == .null) is_nullable = true;
    }
    const declaring = this.get("__declaring_class");
    const self_class: ?[]const u8 = if (declaring == .string and declaring.string.bytes().len > 0) declaring.string.bytes() else null;
    const obj = try createTypeObj(ctx, type_val.string.bytes(), is_nullable, self_class);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rpIsDefaultValueAvailable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const has_default = this.get("__has_default");
    return NativeResult.scalar(.{ .bool = has_default == .bool and has_default.bool });
}

fn rpGetDefaultValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const has_default = this.get("__has_default");
    if (has_default != .bool or !has_default.bool) return throwReflection(ctx, "Internal error: Failed to retrieve the default value");
    // a user function's default is evaluated when asked for, as php does:
    // constants resolve then, and an unresolvable one throws then
    const lazy_func = this.get("__default_func");
    if (lazy_func == .int) {
        const func: *const ObjFunction = @ptrFromInt(@as(usize, @intCast(lazy_func.int)));
        return NativeResult.share(try ctx.vm.resolveParamDefault(func, @intCast(this.get("__default_index").int)));
    }
    return NativeResult.share(this.get("__default_value"));
}

fn rpIsOptional(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const optional = this.get("__optional");
    if (optional == .bool) return NativeResult.scalar(optional);
    const has_default = this.get("__has_default");
    if (has_default == .bool and has_default.bool) return NativeResult.scalar(.{ .bool = true });
    const is_var = this.get("__is_variadic");
    return NativeResult.scalar(.{ .bool = is_var == .bool and is_var.bool });
}

fn rpGetPosition(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.share(this.get("__position"));
}

fn rpAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const type_val = this.get("__type_name");
    if (type_val != .string or type_val.string.bytes().len == 0) return NativeResult.scalar(.{ .bool = true });
    if (std.mem.eql(u8, type_val.string.bytes(), "mixed") or std.mem.eql(u8, type_val.string.bytes(), "null")) return NativeResult.scalar(.{ .bool = true });
    const nullable = this.get("__nullable");
    return NativeResult.scalar(.{ .bool = nullable == .bool and nullable.bool });
}

fn rpIsPassedByReference(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const by_ref = this.get("__by_reference");
    return NativeResult.scalar(.{ .bool = by_ref == .bool and by_ref.bool });
}

fn rpCanBePassedByValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const by_ref = this.get("__by_reference");
    return NativeResult.scalar(.{ .bool = !(by_ref == .bool and by_ref.bool) });
}

fn rpHasType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const type_val = this.get("__type_name");
    return NativeResult.scalar(.{ .bool = type_val == .string and type_val.string.bytes().len > 0 });
}

// constant default sentinel: "\x00CC\x00<class>\x00<const>" (class empty for global constants)
// returns "CONST" for global, "Class::CONST" for class constants
fn decodeConstSentinel(ctx: *NativeContext, v: Value) !?[]const u8 {
    if (v != .string) return null;
    const s = v.string.bytes();
    if (s.len <= 4 or s[0] != 0 or s[1] != 'C' or s[2] != 'C' or s[3] != 0) return null;
    const rest = s[4..];
    const sep = std.mem.lastIndexOfScalar(u8, rest, 0) orelse return null;
    const class_name = rest[0..sep];
    const const_name = rest[sep + 1 ..];
    if (class_name.len == 0) return try ctx.vm.internName(const_name);
    // kept by the parameter object, so it must outlive this call
    const full = try std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ class_name, const_name });
    defer ctx.allocator.free(full);
    return try ctx.vm.internName(full);
}

fn rpIsDefaultValueConstant(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const has_default = this.get("__has_default");
    if (has_default != .bool or !has_default.bool) return throwReflection(ctx, "Internal error: Failed to retrieve the default value");
    const name = this.get("__default_const_name");
    return NativeResult.scalar(.{ .bool = name == .string and name.string.bytes().len > 0 });
}

fn rpGetDefaultValueConstantName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const has_default = this.get("__has_default");
    if (has_default != .bool or !has_default.bool) return throwReflection(ctx, "Internal error: Failed to retrieve the default value");
    const name = this.get("__default_const_name");
    if (name == .string and name.string.bytes().len > 0) return NativeResult.share(name);
    return NativeResult.scalar(.null);
}

fn rpGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try checkAttributeFilter(ctx, args, "ReflectionParameter");
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const param_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter_arg: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags_arg: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    if (this.get("__declaring_class") != .string) {
        // a function's or closure's parameter
        const function = this.get("__function");
        if (function != .string) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
        const key = try bytecode.paramAttributesName(ctx.allocator, compiledFunctionName(ctx.vm, function.string.bytes()), param_name);
        defer ctx.allocator.free(key);
        const attrs = ctx.vm.function_attributes.get(key) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
        const scope = this.get("__attribute_scope");
        return buildAttributeArrayWithFlags(ctx, attrs, filter_arg, 32, flags_arg, if (scope == .string) scope.string.bytes() else "");
    }
    const class_name = this.get("__declaring_class").string.bytes();
    const method_name = if (this.get("__method_name") == .string) this.get("__method_name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    var key_buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{s}:{s}", .{ method_name, param_name }) catch return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const own = if (ctx.vm.classes.get(class_name)) |cls| cls.param_attributes.get(key) else null;
    const attrs = own orelse blk: {
        // a method taken from a trait: its parameters' are filed under the
        // trait's method
        const method_key = class_names.memberKey(&key_buf, class_name, method_name);
        const func = ctx.vm.functions.get(method_key) orelse break :blk null;
        const trait_key = try bytecode.paramAttributesName(ctx.allocator, if (func.trait_origin.len > 0) func.trait_origin else func.name, param_name);
        defer ctx.allocator.free(trait_key);
        break :blk ctx.vm.function_attributes.get(trait_key);
    } orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 32, flags, class_name);
}

fn rpGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const declaring = this.get("__declaring_class");
    if (declaring != .string or declaring.string.bytes().len == 0) return NativeResult.scalar(.null);

    const obj = try classObject(ctx, declaring.string.bytes());
    return NativeResult.borrowed(.{ .object = obj });
}

fn rpIsVariadic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = this.get("__is_variadic");
    return NativeResult.scalar(.{ .bool = v == .bool and v.bool });
}

fn rpGetDeclaringFunction(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const hook = this.get("__hook_declaring_function");
    if (hook == .object) return NativeResult.share(hook);
    const closure = this.get("__closure");
    if (closure.closureName() != null) {
        if (this.get("__closure_method") == .bool) {
            const obj = try ctx.createObject("ReflectionMethod");
            try setClosureInvokeMethod(ctx, obj, closure);
            return NativeResult.borrowed(.{ .object = obj });
        }
        const obj = try ctx.createObject("ReflectionFunction");
        _ = try ctx.callMethod(obj, "__construct", &.{closure});
        return NativeResult.borrowed(.{ .object = obj });
    }
    // the names outlive this parameter, which may be freed first
    const func_name = try ctx.vm.internName(if (this.get("__function") == .string) this.get("__function").string.bytes() else "");
    const declaring = try ctx.vm.internName(if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else "");
    if (declaring.len > 0) {
        const obj = try ctx.createObject("ReflectionMethod");
        var buf: [256]u8 = undefined;
        const full = try ctx.vm.internName(class_names.memberKey(&buf, declaring, func_name));
        _ = try initMethodReflection(ctx, obj, &.{.{ .string = Value.String.borrowed(full) }}, false);
        return NativeResult.borrowed(.{ .object = obj });
    }
    const obj = try ctx.createObject("ReflectionFunction");
    _ = try ctx.callMethod(obj, "__construct", &.{.{ .string = Value.String.borrowed(func_name) }});
    return NativeResult.borrowed(.{ .object = obj });
}

fn rntGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("__type_name"));
}

fn rntToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name_v = this.get("__type_name");
    if (name_v != .string) return NativeResult.share(name_v);
    const nullable_v = this.get("__nullable");
    const is_nullable = nullable_v == .bool and nullable_v.bool;
    if (!is_nullable or std.mem.eql(u8, name_v.string.bytes(), "mixed") or std.mem.eql(u8, name_v.string.bytes(), "null")) return NativeResult.share(name_v);
    const result = std.fmt.allocPrint(ctx.allocator, "?{s}", .{name_v.string.bytes()}) catch return NativeResult.share(name_v);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn rntIsBuiltin(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = this.get("__type_name");
    if (name != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = isBuiltinType(name.string.bytes()) });
}

fn rntAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const nullable = this.get("__nullable");
    if (nullable == .bool and nullable.bool) return NativeResult.scalar(.{ .bool = true });
    // mixed and null types implicitly allow null
    const tn = this.get("__type_name");
    if (tn == .string) {
        if (std.mem.eql(u8, tn.string.bytes(), "mixed") or std.mem.eql(u8, tn.string.bytes(), "null")) {
            return NativeResult.scalar(.{ .bool = true });
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rutGetTypes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const ts_v = this.get("__type_str");
    if (ts_v != .string) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const sc_v = this.get("__self_class");
    const self_class: ?[]const u8 = if (sc_v == .string and sc_v.string.bytes().len > 0) sc_v.string.bytes() else null;
    const arr = try ctx.createArray();
    var it = std.mem.splitScalar(u8, ts_v.string.bytes(), '|');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (part[0] == '(') {
            try arr.append(ctx.allocator, .{ .object = try createTypeObj(ctx, std.mem.trim(u8, part, "()"), false, self_class) });
            continue;
        }
        const obj = try createNamedTypeObj(ctx, part, false);
        if (self_class) |sc| {
            if (std.mem.eql(u8, part, "self")) {
                try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed(sc) });
            }
        }
        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rutAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const nullable = this.get("__nullable");
    return NativeResult.scalar(.{ .bool = nullable == .bool and nullable.bool });
}

fn rutToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ts_v = this.get("__type_str");
    return NativeResult.share(ts_v);
}

fn ritGetTypes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const ts_v = this.get("__type_str");
    if (ts_v != .string) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const arr = try ctx.createArray();
    var it = std.mem.splitScalar(u8, ts_v.string.bytes(), '&');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const obj = try createNamedTypeObj(ctx, part, false);
        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn ritAllowsNull(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = false });
}

fn ritToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ts_v = this.get("__type_str");
    return NativeResult.share(ts_v);
}

fn rfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const label = "ReflectionFunction::__construct";
    // Z_PARAM_OBJ_OF_CLASS_OR_STR(Closure)
    if (!isClosureValue(args[0])) {
        const name = (try zpp.scalarString(ctx, label, args, 0, "function", "Closure|string")) orelse return zpp.typeError(ctx, label, 0, "function", "Closure|string", args[0]);
        if (ctx.vm.canonicalFunctionName(name) == null or std.mem.startsWith(u8, name, "__closure_")) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Function {s}() does not exist", .{name});
            defer ctx.allocator.free(msg);
            return throwReflection(ctx, msg);
        }
        if (args[0] != .string) return rfConstruct(ctx, &.{.{ .string = Value.String.borrowed(name) }});
    }

    if (args[0].closureName()) |instance| {
        // php names a closure `{closure:...}`; the Closure object, which
        // this keeps alive while reflected, is internal state
        try this.set(ctx.allocator, "__closure", args[0]);
        const display = if (ctx.vm.functions.get(instance)) |func| func.display_name else "";
        try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(if (display.len > 0) display else "{closure}") });
    } else if (args[0] == .object and std.mem.eql(u8, args[0].object.class_name, "Closure")) {
        const callable = args[0].object.get("__callable");
        // a first-class callable reflects as a closure of the function
        try this.set(ctx.allocator, "__from_closure", .{ .bool = true });
        if (callable == .string) {
            try this.set(ctx.allocator, "name", callable);
        } else if (callable == .array and callable.array.entries.items.len == 2 and callable.array.entries.items[1].value == .string) {
            const target = callable.array.entries.items[0].value;
            const method = callable.array.entries.items[1].value.string.bytes();
            const class_name = if (target == .object) target.object.class_name else if (target == .string) target.string.bytes() else "";
            const full = std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ class_name, method }) catch return NativeResult.scalar(.null);
            defer ctx.allocator.free(full);
            try this.setCopiedString(ctx.allocator, "name", full);
            try this.set(ctx.allocator, "__is_method_ref", .{ .bool = true });
            if (target == .object) {
                try this.set(ctx.allocator, "__scope_class", .{ .string = Value.String.borrowed(class_name) });
                try this.set(ctx.allocator, "__closure_this", target);
            }
        } else return throwReflection(ctx, "ReflectionFunction::__construct() expects a function name");
    } else if (args[0] == .string) {
        const func_name = ctx.vm.canonicalFunctionName(args[0].string.bytes()) orelse
            return throwReflection(ctx, "Function does not exist");
        try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(func_name) });
    } else if (args[0] == .array) {
        // array callable [$obj, 'method'] - store as method reference
        const arr = args[0].array;
        if (arr.entries.items.len == 2 and arr.entries.items[1].value == .string) {
            const method = arr.entries.items[1].value.string.bytes();
            const target = arr.entries.items[0].value;
            const class_name = if (target == .object) target.object.class_name else if (target == .string) target.string.bytes() else "";
            const full = std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ class_name, method }) catch return NativeResult.scalar(.null);
            defer ctx.allocator.free(full);
            try this.setCopiedString(ctx.allocator, "name", full);
            try this.set(ctx.allocator, "__is_method_ref", .{ .bool = true });
            if (target == .object) {
                try this.set(ctx.allocator, "__scope_class", .{ .string = Value.String.borrowed(class_name) });
            }
        } else {
            return throwReflection(ctx, "ReflectionFunction::__construct() expects a function name");
        }
    } else {
        return throwReflection(ctx, "ReflectionFunction::__construct() expects a function name");
    }
    return NativeResult.scalar(.null);
}

// the name a ReflectionFunction looks its function up by: a closure's
// instance, else the function's name
pub fn functionKey(this: *PhpObject) Value {
    if (this.get("__closure").closureName()) |instance| return .{ .string = Value.String.borrowed(instance) };
    return this.get("name");
}

fn rfInvoke(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fn_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callByName(fn_name, args));
}

fn rfInvokeArgs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fn_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.null);
    const arr = try zpp.array(ctx, "ReflectionFunction::invokeArgs", args, 0, "args");
    var bound = try bindArguments(ctx, fn_name, fn_name, &.{}, arr);
    defer bound.deinit(ctx.allocator);
    return NativeResult.share(try ctx.vm.callByName(fn_name, bound.list.items));
}

fn rfGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = this.get("name");
    // a closure is held by its instance name; php reports `{closure:...}`
    if (name == .string) if (ctx.vm.functions.get(name.string.bytes())) |func| if (func.display_name.len > 0) return NativeResult.copyString(ctx.allocator, func.display_name);
    return NativeResult.share(name);
}

fn rfGetParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.null);

    const func = ctx.vm.functions.get(func_name) orelse {
        if (native_params.get(func_name)) |sig| return NativeResult.borrowed(try buildNativeParamArray(ctx, sig, func_name));
        return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    };
    const params = try buildParamArray(ctx, func, func_name);
    const scope = functionAttributeScope(ctx, this, func_name);
    const closure = this.get("__closure");
    if (params == .array) for (params.array.entries.items) |entry| {
        if (entry.value == .object) try entry.value.object.setCopiedString(ctx.allocator, "__attribute_scope", scope);
        if (entry.value == .object and closure.closureName() != null) try entry.value.object.set(ctx.allocator, "__closure", closure);
    };
    return NativeResult.borrowed(params);
}

// the name a function was compiled under, which its attributes are filed
// by: a closure instance (bound ones included) shares its function, a
// class's copy of a trait method keeps the trait's
fn compiledFunctionName(vm: *VM, name: []const u8) []const u8 {
    if (vm.functions.get(name)) |func| return if (func.trait_origin.len > 0) func.trait_origin else func.name;
    return vm.getOrigClosureName(name);
}

// the class a function's attributes are evaluated in: a closure's scope,
// none for a plain function
fn functionAttributeScope(ctx: *NativeContext, this: *PhpObject, func_name: []const u8) []const u8 {
    if (this.get("__scope_class") == .string) return this.get("__scope_class").string.bytes();
    return ctx.vm.closureScopeByName(func_name) orelse "";
}

fn rfGetReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.null);

    const return_type = if (closureAwareTypeInfo(func_name)) |ti| ti.return_type else nativeReturnType(ctx, func_name);
    if (return_type.len == 0) return NativeResult.scalar(.null);

    const obj = try createTypeObj(ctx, return_type, false, null);
    return NativeResult.borrowed(.{ .object = obj });
}

// a built-in's declared return type, from the signature table
fn nativeReturnType(ctx: *NativeContext, name: []const u8) []const u8 {
    if (ctx.vm.functions.contains(name)) return "";
    const sig = native_params.get(name) orelse return "";
    return sig.returns;
}

pub fn closureAwareTypeInfo(func_name: []const u8) ?@TypeOf(vm_mod.getTypeInfo("").?) {
    if (vm_mod.getTypeInfo(func_name)) |ti| return ti;
    if (std.mem.startsWith(u8, func_name, "__closure_")) {
        const after = func_name["__closure_".len..];
        if (std.mem.lastIndexOf(u8, after, "_")) |us| {
            const trimmed = func_name[0 .. "__closure_".len + us];
            return vm_mod.getTypeInfo(trimmed);
        }
    }
    return null;
}

fn rfHasReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .bool = false });

    const return_type = if (closureAwareTypeInfo(func_name)) |ti| ti.return_type else nativeReturnType(ctx, func_name);
    return NativeResult.scalar(.{ .bool = return_type.len > 0 });
}

fn rfGetNumberOfParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .int = 0 });
    const func = ctx.vm.functions.get(func_name) orelse {
        const sig = native_params.get(func_name) orelse return NativeResult.scalar(.{ .int = 0 });
        return NativeResult.scalar(.{ .int = @intCast(sig.params.len) });
    };
    return NativeResult.scalar(.{ .int = func.arity });
}

fn rfGetNumberOfRequiredParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .int = 0 });
    const func = ctx.vm.functions.get(func_name) orelse {
        const sig = native_params.get(func_name) orelse return NativeResult.scalar(.{ .int = 0 });
        return NativeResult.scalar(.{ .int = @intCast(nativeRequiredCount(sig)) });
    };
    return NativeResult.scalar(.{ .int = func.required_params });
}

fn nativeRequiredCount(sig: native_params.Signature) usize {
    var n: usize = 0;
    for (sig.params) |p| {
        if (p.default == .required and !p.variadic) n += 1;
    }
    return n;
}

// internal builtins (registered in vm.native_fns) have no file/line. user-
// defined functions live in vm.functions and carry the source path on their
// ObjFunction. start line comes from the first instruction's stored line
fn rfGetFileName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = functionKey(this);
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(name_v.string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.file_path.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, func.file_path);
}

fn rfGetStartLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = functionKey(this);
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(name_v.string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.start_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(func.start_line) });
}

fn rfGetEndLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = functionKey(this);
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(name_v.string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.end_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(func.end_line) });
}

fn rfGetNamespaceName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.literal("");
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.literal("");
    const name = name_v.string.bytes();
    const last_bs = std.mem.lastIndexOfScalar(u8, name, '\\') orelse return NativeResult.literal("");
    return try NativeResult.copyString(ctx.allocator, name[0..last_bs]);
}

fn rfGetShortName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.literal("");
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.literal("");
    const name = name_v.string.bytes();
    const last_bs = std.mem.lastIndexOfScalar(u8, name, '\\') orelse return NativeResult.shareString(name_v.string);
    return try NativeResult.copyString(ctx.allocator, name[last_bs + 1 ..]);
}

fn rfInNamespace(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = std.mem.indexOfScalar(u8, name_v.string.bytes(), '\\') != null });
}

fn rfIsAnonymous(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = std.mem.startsWith(u8, name, "__closure_") });
}

fn rfIsInternal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // built-in native functions register in vm.native_fns. user functions
    // land in vm.functions. closures sit under __closure_ keys which are
    // also user-defined
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (std.mem.startsWith(u8, name, "__closure_")) return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.functions.contains(name)) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = ctx.vm.native_fns.contains(name) });
}

fn rfIsUserDefined(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const internal = (try rfIsInternal(ctx, &.{})).value;
    return NativeResult.scalar(.{ .bool = !(internal == .bool and internal.bool) });
}

fn rfIsGenerator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(func_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.is_generator });
}

// internal functions don't return by reference
fn rfReturnsReference(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(func_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.returns_ref });
}

fn rfIsVariadic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(func_name) orelse {
        const sig = native_params.get(func_name) orelse return NativeResult.scalar(.{ .bool = false });
        for (sig.params) |p| if (p.variadic) return NativeResult.scalar(.{ .bool = true });
        return NativeResult.scalar(.{ .bool = false });
    };
    return NativeResult.scalar(.{ .bool = func.is_variadic });
}

fn rfGetStaticVariables(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return closureVariables(ctx, true);
}

// the variables a closure binds with `use`
fn rfGetClosureUsedVariables(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return closureVariables(ctx, false);
}

fn closureVariables(ctx: *NativeContext, statics: bool) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const fn_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const result = try ctx.createArray();
    for (ctx.vm.captures.items) |cap| {
        if (std.mem.eql(u8, cap.closure_name, fn_name)) {
            const name = if (cap.var_name.len > 0 and cap.var_name[0] == '$') cap.var_name[1..] else cap.var_name;
            if (std.mem.eql(u8, name, "this")) continue;
            const val = if (cap.ref_cell) |rc| rc.* else cap.value;
            try result.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, val);
        }
    }
    if (statics) try appendStaticVariables(ctx, result, fn_name);
    return NativeResult.borrowed(.{ .array = result });
}

// the static variables a function declares, at their current values or the
// initial ones php shows before the declaration runs
fn appendStaticVariables(ctx: *NativeContext, result: *PhpArray, fn_name: []const u8) RuntimeError!void {
    const func = ctx.vm.functions.get(fn_name) orelse return;
    for (func.static_vars) |sv| {
        var buf: [256]u8 = undefined;
        const storage = class_names.memberKey(&buf, fn_name, sv.name);
        const value = if (ctx.vm.statics_cells.get(storage)) |cell| cell.* else if (ctx.vm.statics.get(storage)) |v| v else try ctx.vm.resolveDefault(sv.initial);
        const key = if (sv.name.len > 0 and sv.name[0] == '$') sv.name[1..] else sv.name;
        try result.setCopiedKey(ctx.allocator, key, value);
    }
}

fn rmGetStaticVariables(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const result = try ctx.createArray();
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = result });
    const method_name = methodLookupName(this) orelse return NativeResult.borrowed(.{ .array = result });
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.borrowed(.{ .array = result });
    var buf: [512]u8 = undefined;
    const fn_name = methodKey(this, &buf, declaring, method_name);
    const registered = ctx.vm.resolveMethod(declaring, method_name) catch null;
    try appendStaticVariables(ctx, result, registered orelse fn_name);
    return NativeResult.borrowed(.{ .array = result });
}

fn reflectionClassNamed(ctx: *NativeContext, class: ?[]const u8) RuntimeError!NativeResult {
    const name = class orelse return NativeResult.scalar(.null);
    const obj = try ctx.createObject("ReflectionClass");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(ctx.vm.declaredClassName(name)) });
    return NativeResult.borrowed(.{ .object = obj });
}

fn rfGetClosureCalledClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (this.get("__closure").closureName()) |instance| return reflectionClassNamed(ctx, ctx.vm.closureScopeByName(instance));
    if (this.get("__scope_class") == .string) {
        const scope_name = this.get("__scope_class").string.bytes();
        const obj = try classObject(ctx, scope_name);
        return NativeResult.borrowed(.{ .object = obj });
    }
    return NativeResult.scalar(.null);
}

fn rfGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try checkAttributeFilter(ctx, args, "ReflectionFunctionAbstract");
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const compile_name = compiledFunctionName(ctx.vm, func_name);
    const attrs = ctx.vm.function_attributes.get(compile_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 2, flags, functionAttributeScope(ctx, this, func_name));
}

fn rfGetClosureScopeClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.null);
    // the class a closure runs in, which binding can change
    if (this.get("__closure").closureName()) |instance| return reflectionClassNamed(ctx, ctx.vm.closureDefClassByName(instance));
    if (this.get("__scope_class") == .string) {
        const scope_name = this.get("__scope_class").string.bytes();
        const obj = try classObject(ctx, scope_name);
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (ctx.vm.closureScopeByName(name)) |scope| {
        const obj = try classObject(ctx, scope);
        return NativeResult.borrowed(.{ .object = obj });
    }
    return NativeResult.scalar(.null);
}

fn rfGetClosureThis(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (this.get("__closure_this") == .object) return NativeResult.share(this.get("__closure_this"));
    const name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.null);
    return NativeResult.share(ctx.vm.closureThisByName(name));
}

fn rfIsStatic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    // a closure declared `static`
    const instance = this.get("__closure").closureName() orelse return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(instance) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.is_static });
}

/// populate fields on a ReflectionParameter `this` object from a function +
/// param index. shared between buildParamArray (constructing the full set for
/// getParameters) and the public ReflectionParameter::__construct
fn populateRpFields(ctx: *NativeContext, obj: *PhpObject, func: *const ObjFunction, type_key: []const u8, i: usize) RuntimeError!void {
    const effective_key = if (std.mem.startsWith(u8, type_key, "__closure_")) blk: {
        const after_prefix = type_key["__closure_".len..];
        if (std.mem.lastIndexOf(u8, after_prefix, "_")) |last_us| {
            break :blk type_key[0 .. "__closure_".len + last_us];
        }
        break :blk type_key;
    } else type_key;
    const type_info = vm_mod.getTypeInfo(effective_key) orelse vm_mod.getTypeInfo(type_key) orelse vm_mod.getTypeInfo(func.name);

    const param_name = func.params[i];
    const clean_name = if (param_name.len > 0 and param_name[0] == '$') param_name[1..] else param_name;
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(clean_name) });
    try obj.set(ctx.allocator, "__position", .{ .int = @intCast(i) });

    if (type_info) |ti| {
        if (i < ti.param_types.len and ti.param_types[i].len > 0) {
            const raw_type = ti.param_types[i];
            if (raw_type[0] == '?') {
                try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed(raw_type[1..]) });
                try obj.set(ctx.allocator, "__nullable", .{ .bool = true });
            } else {
                try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed(raw_type) });
                try obj.set(ctx.allocator, "__nullable", .{ .bool = false });
            }
        } else {
            try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed("") });
            try obj.set(ctx.allocator, "__nullable", .{ .bool = false });
        }
    } else {
        try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed("") });
        try obj.set(ctx.allocator, "__nullable", .{ .bool = false });
    }

    const is_variadic = func.is_variadic and i == func.arity - 1;
    try obj.set(ctx.allocator, "__is_variadic", .{ .bool = is_variadic });

    const has_default = !is_variadic and i >= func.required_params;
    try obj.set(ctx.allocator, "__has_default", .{ .bool = has_default });
    if (has_default and i < func.defaults.len) {
        const raw = func.defaults[i];
        try setLazyDefault(ctx, obj, func, i);
        if (try decodeConstSentinel(ctx, raw)) |const_name| {
            try obj.set(ctx.allocator, "__default_const_name", .{ .string = Value.String.borrowed(const_name) });
        }
    }

    const by_ref = if (i < func.ref_params.len) func.ref_params[i] else false;
    try obj.set(ctx.allocator, "__by_reference", .{ .bool = by_ref });

    if (std.mem.indexOf(u8, type_key, "::")) |sep| {
        const decl_class = try ctx.allocator.dupe(u8, type_key[0..sep]);
        defer ctx.allocator.free(decl_class);
        try obj.setCopiedString(ctx.allocator, "__declaring_class", decl_class);
        const meth_name = try ctx.allocator.dupe(u8, type_key[sep + 2 ..]);
        defer ctx.allocator.free(meth_name);
        try obj.setCopiedString(ctx.allocator, "__method_name", meth_name);
        try obj.setCopiedString(ctx.allocator, "__function", meth_name);
    } else {
        const fname = try ctx.allocator.dupe(u8, type_key);
        defer ctx.allocator.free(fname);
        try obj.setCopiedString(ctx.allocator, "__function", fname);
    }
}

fn rpConstructParam(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const label = "ReflectionParameter::__construct";
    // Z_PARAM_STR_OR_LONG
    const param = args[1];
    const by_name: ?[]const u8 = switch (param) {
        .int => null,
        .float => |f| if (std.math.isFinite(f) and @floor(f) == f) null else (try zpp.scalarString(ctx, label, args, 1, "param", "string|int")),
        .bool => null,
        else => (try zpp.scalarString(ctx, label, args, 1, "param", "string|int")) orelse return zpp.typeError(ctx, label, 1, "param", "string|int", param),
    };
    const position: i64 = switch (param) {
        .int => |n| n,
        .float => |f| if (by_name == null) @intFromFloat(f) else 0,
        .bool => |b| @intFromBool(b),
        else => 0,
    };

    // first, find the function: a name, [class or object, method], or a
    // callable object
    var key_buf: [256]u8 = undefined;
    var lookup_key: []const u8 = "";
    const reference = args[0];
    if (reference.closureName()) |instance| {
        const result = try finishParameter(ctx, this, label, instance, by_name, position);
        try this.set(ctx.allocator, "__closure", reference);
        return result;
    } else switch (reference) {
        .string => |sv| {
            lookup_key = ctx.vm.canonicalFunctionName(sv.bytes()) orelse {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Function {s}() does not exist", .{sv.bytes()});
                defer ctx.allocator.free(msg);
                return throwReflection(ctx, msg);
            };
        },
        .array => |arr| {
            if (!arr.contains(.{ .int = 0 }) or !arr.contains(.{ .int = 1 })) return throwReflection(ctx, "Expected array($object, $method) or array($classname, $method)");
            const classref: ?Value = arr.get(.{ .int = 0 });
            const method: ?Value = arr.get(.{ .int = 1 });
            // a closure's __invoke is the closure
            if (classref.?.closureName() != null and method.? == .string and isInvokeName(method.?.string.bytes())) {
                lookup_key = classref.?.closureName().?;
                const result = try finishParameter(ctx, this, label, lookup_key, by_name, position);
                try this.set(ctx.allocator, "__closure", classref.?);
                try this.set(ctx.allocator, "__closure_method", .{ .bool = true });
                return result;
            }
            const class_name = if (classref.? == .object) classref.?.object.class_name else blk: {
                const text = (try zpp.scalarString(ctx, label, &.{classref.?}, 0, "function", "string")) orelse return zpp.typeError(ctx, label, 0, "function", "string", classref.?);
                break :blk (try lookupClass(ctx, text)) orelse {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" does not exist", .{text});
                    defer ctx.allocator.free(msg);
                    return throwReflection(ctx, msg);
                };
            };
            const method_name = (try zpp.scalarString(ctx, label, &.{method.?}, 0, "function", "string")) orelse return zpp.typeError(ctx, label, 0, "function", "string", method.?);
            if (!ctx.vm.hasMethod(class_name, method_name)) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Method {s}::{s}() does not exist", .{ class_name, method_name });
                defer ctx.allocator.free(msg);
                return throwReflection(ctx, msg);
            }
            const declared = declaredMethodName(ctx.vm, class_name, method_name);
            lookup_key = try ctx.vm.internName(class_names.memberKey(&key_buf, findDeclaringClass(ctx.vm, class_name, declared), declared));
        },
        .object => |o| {
            if (!ctx.vm.hasMethod(o.class_name, "__invoke")) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Method {s}::__invoke() does not exist", .{o.class_name});
                defer ctx.allocator.free(msg);
                return throwReflection(ctx, msg);
            }
            const declared = declaredMethodName(ctx.vm, o.class_name, "__invoke");
            lookup_key = try ctx.vm.internName(class_names.memberKey(&key_buf, findDeclaringClass(ctx.vm, o.class_name, declared), declared));
        },
        else => {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #1 ($function) must be a string, an array(class, method), or a callable object, {s} given", .{ label, reference.valueName() });
            defer ctx.allocator.free(msg);
            return throwReflection(ctx, msg);
        },
    }

    return finishParameter(ctx, this, label, lookup_key, by_name, position);
}

// the parameter of the function found, by name or position
fn finishParameter(ctx: *NativeContext, this: *PhpObject, label: []const u8, lookup_key: []const u8, by_name: ?[]const u8, position: i64) RuntimeError!NativeResult {
    _ = label;
    const user = ctx.vm.functions.get(lookup_key);
    const sig = if (user == null) native_params.get(lookup_key) else null;
    if (user == null and sig == null) return throwReflection(ctx, "The parameter specified by its offset could not be found");
    const count: usize = if (user) |f| f.params.len else sig.?.params.len;
    var index: usize = 0;
    if (by_name) |want| {
        index = for (0..count) |i| {
            const pname = if (user) |f| std.mem.trimStart(u8, f.params[i], "$") else sig.?.params[i].name;
            if (std.mem.eql(u8, pname, want)) break i;
        } else return throwReflection(ctx, "The parameter specified by its name could not be found");
    } else {
        if (position < 0) {
            _ = try ctx.vm.throwBuiltinException("ValueError", "ReflectionParameter::__construct(): Argument #2 ($param) must be greater than or equal to 0");
            return error.RuntimeError;
        }
        if (position >= count) return throwReflection(ctx, "The parameter specified by its offset could not be found");
        index = @intCast(position);
    }
    if (user) |f| {
        try populateRpFields(ctx, this, f, lookup_key, index);
    } else {
        try populateNativeRpFields(ctx, this, sig.?, lookup_key, index);
    }
    return NativeResult.scalar(.null);
}

fn buildNativeParamArray(ctx: *NativeContext, sig: native_params.Signature, key: []const u8) RuntimeError!Value {
    const arr = try ctx.createArray();
    for (0..sig.params.len) |i| {
        const obj = try ctx.createObject("ReflectionParameter");
        try populateNativeRpFields(ctx, obj, sig, key, i);
        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return .{ .array = arr };
}

// the same fields buildParamArray sets for a user parameter, read from a
// built-in's signature. an optional parameter whose default php does not
// publish is optional without an available default
fn populateNativeRpFields(ctx: *NativeContext, obj: *PhpObject, sig: native_params.Signature, key: []const u8, i: usize) RuntimeError!void {
    const p = sig.params[i];
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(p.name) });
    try obj.set(ctx.allocator, "__position", .{ .int = @intCast(i) });
    const nullable_prefix = p.type.len > 0 and p.type[0] == '?';
    const type_name = if (nullable_prefix) p.type[1..] else p.type;
    const in_union = std.mem.indexOf(u8, type_name, "|null") != null or std.mem.startsWith(u8, type_name, "null|");
    try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed(type_name) });
    try obj.set(ctx.allocator, "__nullable", .{ .bool = nullable_prefix or in_union });
    try obj.set(ctx.allocator, "__is_variadic", .{ .bool = p.variadic });
    const has_default = !p.variadic and p.default != .required and p.default != .unknown;
    try obj.set(ctx.allocator, "__has_default", .{ .bool = has_default });
    try obj.set(ctx.allocator, "__optional", .{ .bool = p.variadic or p.default != .required });
    if (has_default) try obj.set(ctx.allocator, "__default_value", try ctx.vm.nativeDefault(p.default));
    if (p.default_constant.len > 0) try obj.set(ctx.allocator, "__default_const_name", .{ .string = Value.String.borrowed(p.default_constant) });
    try obj.set(ctx.allocator, "__by_reference", .{ .bool = p.by_ref });
    if (std.mem.indexOf(u8, key, "::")) |sep| {
        try obj.set(ctx.allocator, "__declaring_class", .{ .string = Value.String.borrowed(try ctx.vm.stableClassName(key[0..sep])) });
        const method_name = try ctx.vm.internName(key[sep + 2 ..]);
        try obj.set(ctx.allocator, "__method_name", .{ .string = Value.String.borrowed(method_name) });
        try obj.set(ctx.allocator, "__function", .{ .string = Value.String.borrowed(method_name) });
    } else {
        try obj.set(ctx.allocator, "__function", .{ .string = Value.String.borrowed(try ctx.vm.internName(key)) });
    }
}

fn buildParamArray(ctx: *NativeContext, func: *const ObjFunction, type_key: []const u8) RuntimeError!Value {
    const arr = try ctx.createArray();
    const effective_key = if (std.mem.startsWith(u8, type_key, "__closure_")) blk: {
        const after_prefix = type_key["__closure_".len..];
        if (std.mem.lastIndexOf(u8, after_prefix, "_")) |last_us| {
            break :blk type_key[0 .. "__closure_".len + last_us];
        }
        break :blk type_key;
    } else type_key;
    const type_info = vm_mod.getTypeInfo(effective_key) orelse vm_mod.getTypeInfo(type_key) orelse vm_mod.getTypeInfo(func.name);

    for (func.params, 0..) |param_name, i| {
        const obj = try ctx.createObject("ReflectionParameter");

        const clean_name = if (param_name.len > 0 and param_name[0] == '$') param_name[1..] else param_name;
        try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(clean_name) });
        try obj.set(ctx.allocator, "__position", .{ .int = @intCast(i) });

        if (type_info) |ti| {
            if (i < ti.param_types.len and ti.param_types[i].len > 0) {
                const raw_type = ti.param_types[i];
                if (raw_type[0] == '?') {
                    try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed(raw_type[1..]) });
                    try obj.set(ctx.allocator, "__nullable", .{ .bool = true });
                } else {
                    try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed(raw_type) });
                    try obj.set(ctx.allocator, "__nullable", .{ .bool = false });
                }
            } else {
                try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed("") });
                try obj.set(ctx.allocator, "__nullable", .{ .bool = false });
            }
        } else {
            try obj.set(ctx.allocator, "__type_name", .{ .string = Value.String.borrowed("") });
            try obj.set(ctx.allocator, "__nullable", .{ .bool = false });
        }

        const is_variadic = func.is_variadic and i == func.arity - 1;
        try obj.set(ctx.allocator, "__is_variadic", .{ .bool = is_variadic });

        // default values - defaults array has one entry per param, non-default params have .null
        // variadic params never have a default (they collect remaining args)
        const has_default = !is_variadic and i >= func.required_params;
        try obj.set(ctx.allocator, "__has_default", .{ .bool = has_default });
        if (has_default and i < func.defaults.len) {
            const raw = func.defaults[i];
            try setLazyDefault(ctx, obj, func, i);
            if (try decodeConstSentinel(ctx, raw)) |const_name| {
                try obj.set(ctx.allocator, "__default_const_name", .{ .string = Value.String.borrowed(const_name) });
            }
        }

        const by_ref = if (i < func.ref_params.len) func.ref_params[i] else false;
        try obj.set(ctx.allocator, "__by_reference", .{ .bool = by_ref });

        // declaring class and method name (or bare function name for free fns)
        if (std.mem.indexOf(u8, type_key, "::")) |sep| {
            const decl_class = try ctx.allocator.dupe(u8, type_key[0..sep]);
            defer ctx.allocator.free(decl_class);
            try obj.setCopiedString(ctx.allocator, "__declaring_class", decl_class);
            const meth_name = try ctx.allocator.dupe(u8, type_key[sep + 2 ..]);
            defer ctx.allocator.free(meth_name);
            try obj.setCopiedString(ctx.allocator, "__method_name", meth_name);
            try obj.setCopiedString(ctx.allocator, "__function", meth_name);
        } else {
            const fname = try ctx.allocator.dupe(u8, type_key);
            defer ctx.allocator.free(fname);
            try obj.setCopiedString(ctx.allocator, "__function", fname);
        }

        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return .{ .array = arr };
}

fn closureArgError(ctx: *NativeContext, comptime func: []const u8, comptime param: []const u8, comptime expected: []const u8, given: Value) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "Closure::" ++ func ++ "(): Argument " ++ param ++ " must be of type " ++ expected ++ ", {s} given", .{given.typeName()});
    defer ctx.allocator.free(msg);
    try ctx.vm.setPendingException("TypeError", msg);
    return error.RuntimeError;
}

// Closure::bind($closure, $newThis, $newScope = "static")
fn closureBind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object or !std.mem.eql(u8, args[0].object.class_name, "Closure"))
        return closureArgError(ctx, "bind", "#1 ($closure)", "Closure", if (args.len > 0) args[0] else .null);
    return bindClosure(ctx, "bind", "#2 ($newThis)", "#3 ($newScope)", args[0].object, if (args.len >= 2) args[1] else .null, if (args.len >= 3) args[2] else null);
}

// $closure->bindTo($newThis, $newScope = "static")
fn closureBindTo(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return bindClosure(ctx, "bindTo", "#1 ($newThis)", "#2 ($newScope)", this, if (args.len >= 1) args[0] else .null, if (args.len >= 2) args[1] else null);
}

// do_closure_bind: the scope argument names a class (an object's, "static"
// for the closure's own), the binding is checked, and the copy is bound
fn bindClosure(ctx: *NativeContext, comptime func: []const u8, comptime this_param: []const u8, comptime scope_param: []const u8, closure: *PhpObject, new_this: Value, scope_arg: ?Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    if (new_this != .null and new_this != .object) return closureArgError(ctx, func, this_param, "?object", new_this);
    const instance = closure.closureName();
    const current_scope: ?[]const u8 = if (instance) |name| vm.closureDefClassByName(name) else vm.fakeClosureTarget(closure).scope;
    const scope: ?[]const u8 = if (scope_arg) |arg| switch (arg) {
        .null => null,
        .object => |o| o.class_name,
        .string => |str| blk: {
            const raw = str.bytes();
            if (std.mem.eql(u8, raw, "static")) break :blk current_scope;
            const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
            if (!vm.classes.contains(name)) try vm.tryAutoload(name);
            if (vm.classes.getKey(name)) |declared| break :blk declared;
            const msg = try std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" not found", .{raw});
            defer ctx.allocator.free(msg);
            try vm.emitWarning(msg);
            return NativeResult.scalar(.null);
        },
        else => return closureArgError(ctx, func, scope_param, "object|string|null", arg),
    } else current_scope;
    if (try vm.closureBindingRefusal(closure, new_this, scope)) |msg| {
        defer ctx.allocator.free(msg);
        try vm.emitWarning(msg);
        return NativeResult.scalar(.null);
    }
    const name = instance orelse return bindFakeClosure(ctx, closure, new_this);
    // an object bound without a scope gets Closure as a dummy scope
    const effective_scope: ?[]const u8 = scope orelse if (new_this == .object) @as([]const u8, "Closure") else null;
    const called = if (new_this == .object) new_this.object.class_name else scope;
    return NativeResult.borrowed(vm.disownedClosure(try vm.copyClosureInstance(name, new_this, effective_scope, called)));
}

// a Closure made from a callable, bound anew: a method's now runs on new_this
fn bindFakeClosure(ctx: *NativeContext, closure: *PhpObject, new_this: Value) RuntimeError!NativeResult {
    var callable = closure.get("__callable");
    if (new_this == .object and callable == .array and callable.array.entries.items.len == 2) {
        const pair = try ctx.createArray();
        try pair.append(ctx.allocator, new_this);
        try pair.append(ctx.allocator, callable.array.entries.items[1].value);
        callable = .{ .array = pair };
    }
    return wrapCallableClosure(ctx, callable);
}

// $closure->call($newThis, ...$args): runs bound to $newThis, in its class
fn closureCall(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const new_this = if (args.len >= 1) args[0] else Value.null;
    if (new_this != .object) return closureArgError(ctx, "call", "#1 ($newThis)", "object", new_this);
    const call_args = if (args.len > 1) args[1..] else &.{};
    const scope = new_this.object.class_name;
    if (try vm.closureBindingRefusal(this, new_this, scope)) |msg| {
        defer ctx.allocator.free(msg);
        try vm.emitWarning(msg);
        return NativeResult.scalar(.null);
    }
    const instance = this.closureName() orelse {
        const bound = (try bindFakeClosure(ctx, this, new_this)).value;
        defer vm.discardOrphan(bound);
        return NativeResult.share(try vm.callValueCallable(bound, call_args));
    };
    const bound = try vm.copyClosureInstance(instance, new_this, scope, scope);
    // the temporary bound closure lives for this call only; the callee
    // frame holds it while it runs
    defer vm.releaseValue(bound);
    const name = bound.closureName() orelse return NativeResult.scalar(.null);
    return NativeResult.share(try vm.callByName(name, call_args));
}

// $closure->__invoke(...$args) calls the closure as it is bound
fn closureInvoke(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callValueCallable(.{ .object = this }, args));
}

// zend_closure_get_debug_info: a Closure shows nothing but its debug table
fn closureProperties(ctx: *NativeContext, obj: *PhpObject, purpose: object_properties.Purpose) RuntimeError!?*PhpArray {
    const table = try ctx.vm.allocArray();
    if (purpose != .debug) return table;
    if (obj.closureName()) |instance| {
        try closureInstanceTable(ctx, table, instance);
    } else {
        try callableClosureTable(ctx, table, obj.get("__callable"));
    }
    return table;
}

fn setNamed(ctx: *NativeContext, table: *PhpArray, key: []const u8, value: Value) RuntimeError!void {
    try table.setCopiedKey(ctx.allocator, key, value);
}

// a closure expression's instance: where it was written, what it captured
// and declares static, the object it is bound to, its parameters
fn closureInstanceTable(ctx: *NativeContext, table: *PhpArray, name: []const u8) RuntimeError!void {
    const vm = ctx.vm;
    const func = vm.functions.get(name) orelse return;
    try setNamed(ctx, table, "name", .{ .string = Value.String.borrowed(if (func.display_name.len > 0) func.display_name else "{closure}") });
    try setNamed(ctx, table, "file", .{ .string = Value.String.borrowed(func.file_path) });
    try setNamed(ctx, table, "line", .{ .int = func.start_line });
    const statics = try vm.allocArray();
    if (vm.capture_index.get(name)) |range| {
        for (vm.captures.items[range.start .. range.start + range.len]) |cap| {
            if (std.mem.eql(u8, cap.var_name, "$this") or std.mem.startsWith(u8, cap.var_name, "$__closure")) continue;
            const key = if (cap.var_name.len > 0 and cap.var_name[0] == '$') cap.var_name[1..] else cap.var_name;
            if (cap.ref_cell) |cell| {
                try statics.setCopiedKey(ctx.allocator, key, cell.*);
                if (statics.getPtr(.{ .string = Value.String.borrowed(key) })) |entry| vm.setEntryRef(entry, cell);
            } else try statics.setCopiedKey(ctx.allocator, key, cap.value);
        }
    }
    for (func.static_vars) |sv| {
        var buf: [256]u8 = undefined;
        const storage = class_names.memberKey(&buf, name, sv.name);
        const value = if (vm.statics_cells.get(storage)) |cell| cell.* else if (vm.statics.get(storage)) |v| v else try vm.resolveDefault(sv.initial);
        const key = if (sv.name.len > 0 and sv.name[0] == '$') sv.name[1..] else sv.name;
        try statics.setCopiedKey(ctx.allocator, key, value);
    }
    if (statics.entries.items.len > 0) try setNamed(ctx, table, "static", .{ .array = statics });
    const this = vm.closureThisByName(name);
    if (this == .object) try setNamed(ctx, table, "this", this);
    try parameterTable(ctx, table, func.params, func.ref_params, func.required_params, func.is_variadic);
}

// a Closure made from a callable: the function it calls, and the object for
// a method
fn callableClosureTable(ctx: *NativeContext, table: *PhpArray, callable: Value) RuntimeError!void {
    var function: []const u8 = "";
    var this: Value = .null;
    var buf: [512]u8 = undefined;
    switch (callable) {
        .string => |s| function = s.bytes(),
        .array => |arr| if (arr.entries.items.len == 2) {
            const target = arr.entries.items[0].value;
            const method = arr.entries.items[1].value;
            if (method != .string) return;
            const class = switch (target) {
                .object => |o| blk: {
                    this = target;
                    break :blk o.class_name;
                },
                .string => |cs| cs.bytes(),
                else => return,
            };
            const registered = ctx.vm.resolveMethod(class, method.string.bytes()) catch null;
            function = registered orelse (class_names.memberKey(&buf, class, method.string.bytes()));
        },
        else => return,
    }
    try table.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("function") }, function);
    if (this == .object) try setNamed(ctx, table, "this", this);
    if (ctx.vm.functions.get(function)) |func| {
        try parameterTable(ctx, table, func.params, func.ref_params, func.required_params, func.is_variadic);
    } else if (@import("native_params.zig").get(function)) |signature| {
        const params = try ctx.allocator.alloc([]const u8, signature.params.len);
        defer ctx.allocator.free(params);
        const refs = try ctx.allocator.alloc(bool, signature.params.len);
        defer ctx.allocator.free(refs);
        var names: std.ArrayListUnmanaged([]u8) = .empty;
        defer {
            for (names.items) |n| ctx.allocator.free(n);
            names.deinit(ctx.allocator);
        }
        var required: u8 = 0;
        var variadic = false;
        for (signature.params, 0..) |param, i| {
            const dollar = try std.fmt.allocPrint(ctx.allocator, "${s}", .{param.name});
            try names.append(ctx.allocator, dollar);
            params[i] = dollar;
            refs[i] = param.by_ref;
            if (param.default == .required and !param.variadic) required = @intCast(i + 1);
            if (param.variadic) variadic = true;
        }
        try parameterTable(ctx, table, params, refs, required, variadic);
    }
}

fn parameterTable(ctx: *NativeContext, table: *PhpArray, params: []const []const u8, ref_params: []const bool, required: u8, variadic: bool) RuntimeError!void {
    if (params.len == 0) return;
    const out = try ctx.vm.allocArray();
    for (params, 0..) |param, i| {
        var buf: [256]u8 = undefined;
        const by_ref = i < ref_params.len and ref_params[i];
        const key = std.fmt.bufPrint(&buf, "{s}{s}", .{ if (by_ref) "&" else "", param }) catch continue;
        const optional = i >= required or (variadic and i == params.len - 1);
        try out.setCopiedKey(ctx.allocator, key, .{ .string = Value.String.borrowed(if (optional) "<optional>" else "<required>") });
    }
    try setNamed(ctx, table, "parameter", .{ .array = out });
}

fn wrapCallableClosure(ctx: *NativeContext, callable: Value) RuntimeError!NativeResult {
    const obj = try ctx.createObject("Closure");
    try obj.set(ctx.allocator, "__callable", callable);
    return NativeResult.borrowed(.{ .object = obj });
}

// the closure the calling frame runs, as the same instance it was called
// through; a function reached through a callable isn't one
fn closureGetCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const vm = ctx.vm;
    // the calling frame, under any frame a native static call put on top
    var caller = vm.frame_count;
    while (caller > 1 and vm.frames[caller - 1].func == null) caller -= 1;
    const name = if (caller > 0) vm.frames[caller - 1].call_name else null;
    const closure = if (name) |n| vm.closureObject(n) else null;
    if (closure == null) {
        try vm.setPendingException("Error", "Current function is not a closure");
        return error.RuntimeError;
    }
    return NativeResult.share(.{ .object = closure.? });
}

fn closureFromCallable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.null);
    const callable = args[0];
    if (callable == .object and std.mem.eql(u8, callable.object.class_name, "Closure")) return NativeResult.share(callable);
    if (callable == .string) {
        const raw = callable.string.bytes();
        const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
        if (ctx.vm.canonicalFunctionName(name) orelse ctx.vm.staticMethodNamed(name)) |registered| {
            // the registered name, so later calls find the function whatever
            // case or leading backslash the callable was written with
            if (!std.mem.eql(u8, registered, raw)) return wrapCallableClosure(ctx, .{ .string = Value.String.borrowed(registered) });
            return wrapCallableClosure(ctx, callable);
        }
        try ctx.vm.setPendingException("TypeError", "Failed to create closure from callable: function does not exist");
        return error.RuntimeError;
    }
    if (callable == .object) {
        if (ctx.vm.hasMethod(callable.object.class_name, "__invoke")) return wrapCallableClosure(ctx, callable);
        try ctx.vm.setPendingException("TypeError", "Failed to create closure from callable");
        return error.RuntimeError;
    }
    if (callable == .array) {
        const entries = callable.array.entries.items;
        if (entries.len == 2 and entries[1].value == .string) {
            const method = entries[1].value.string.bytes();
            if (entries[0].value == .string) {
                if (ctx.vm.hasMethod(entries[0].value.string.bytes(), method)) {
                    const full = try ctx.vm.transientAdopted(try std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ entries[0].value.string.bytes(), method }));
                    return wrapCallableClosure(ctx, .{ .string = full });
                }
            } else if (entries[0].value == .object) {
                if (ctx.vm.hasMethod(entries[0].value.object.class_name, method)) return wrapCallableClosure(ctx, callable);
            }
        }
        try ctx.vm.setPendingException("TypeError", "Failed to create closure from callable");
        return error.RuntimeError;
    }
    try ctx.vm.setPendingException("TypeError", "Failed to create closure from callable");
    return error.RuntimeError;
}

fn reflectionNoop(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn reflectionFalse(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = false });
}

pub fn methodLookupName(obj: *PhpObject) ?[]const u8 {
    const internal = obj.get("__hook_method");
    if (internal == .string) return internal.string.bytes();
    const name = obj.get("name");
    return if (name == .string) name.string.bytes() else null;
}

const ReflectedHook = struct {
    declaring: []const u8,
    info: ClassDef.MethodInfo,
};

fn lookupPropertyHook(ctx: *NativeContext, kind: []const u8) ?ReflectedHook {
    const this = getThis(ctx) orelse return null;
    const name = this.get("name");
    const declaring = this.get("__declaring_class");
    if (name != .string or declaring != .string) return null;
    var buf: [512]u8 = undefined;
    const method = std.fmt.bufPrint(&buf, "{s}$hook_{s}", .{ name.string.bytes(), kind }) catch return null;
    const cls = ctx.vm.classes.getPtr(declaring.string.bytes()) orelse return null;
    const hook = ctx.vm.resolvePropertyHook(cls, method) orelse return null;
    return .{ .declaring = hook.declaring, .info = hook.info };
}

fn hookKind(ctx: *NativeContext, args: []const Value) RuntimeError![]const u8 {
    if (args.len > 0 and args[0] == .object and std.mem.eql(u8, args[0].object.class_name, "PropertyHookType")) {
        const name = args[0].object.get("name");
        if (name == .string) {
            if (std.mem.eql(u8, name.string.bytes(), "Get")) return "get";
            if (std.mem.eql(u8, name.string.bytes(), "Set")) return "set";
        }
    }
    _ = try ctx.vm.throwBuiltinException("TypeError", "Argument #1 ($type) must be of type PropertyHookType");
    return error.RuntimeError;
}

fn buildHookObj(ctx: *NativeContext, hook: ReflectedHook, kind: []const u8) !*PhpObject {
    const this = getThis(ctx).?;
    var info = hook.info;
    // PHP exposes hook ReflectionMethods as public, even on private properties.
    info.visibility = .public;
    const obj = try buildMethodObj(ctx, hook.declaring, hook.info.name, info, hook.declaring);
    const display = try std.fmt.allocPrint(ctx.allocator, "${s}::{s}", .{ this.get("name").string.bytes(), kind });
    defer ctx.allocator.free(display);
    try obj.setCopiedString(ctx.allocator, "name", display);
    try obj.set(ctx.allocator, "__hook_method", .{ .string = Value.String.borrowed(hook.info.name) });
    try obj.set(ctx.allocator, "__hook_property", this.get("name"));
    const prop = findPropertyDef(ctx.vm, hook.declaring, this.get("name").string.bytes());
    const return_type = if (std.mem.eql(u8, kind, "set")) "void" else if (prop) |p| p.prop.type_str else "";
    try obj.set(ctx.allocator, "__hook_return_type", .{ .string = Value.String.borrowed(return_type) });
    return obj;
}

fn rpropHasHooks(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = lookupPropertyHook(ctx, "get") != null or lookupPropertyHook(ctx, "set") != null });
}

fn rpropHasHook(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = lookupPropertyHook(ctx, try hookKind(ctx, args)) != null });
}

fn rpropGetHook(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const kind = try hookKind(ctx, args);
    const hook = lookupPropertyHook(ctx, kind) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = try buildHookObj(ctx, hook, kind) });
}

fn rpropGetHooks(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for ([_][]const u8{ "get", "set" }) |kind| {
        if (lookupPropertyHook(ctx, kind)) |hook| {
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(kind) }, .{ .object = try buildHookObj(ctx, hook, kind) });
        }
    }
    return NativeResult.borrowed(.{ .array = arr });
}

// ReflectionReference::fromArrayElement: the element's reference, null for a
// plain value or a reference nothing else binds
fn rrefFromArrayElement(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const label = "ReflectionReference::fromArrayElement";
    const arr = try zpp.array(ctx, label, args, 0, "array");
    const key: PhpArray.Key = switch (args[1]) {
        .int => |n| .{ .int = n },
        .string => |sv| PhpArray.normalizeKey(.{ .string = sv }),
        .bool => |b| .{ .int = @intFromBool(b) },
        .float => |f| if (std.math.isFinite(f) and @floor(f) == f) .{ .int = @intFromFloat(f) } else return zpp.typeError(ctx, label, 1, "key", "string|int", args[1]),
        else => return zpp.typeError(ctx, label, 1, "key", "string|int", args[1]),
    };
    const entry = for (arr.entries.items) |*e| {
        if (e.key.eql(key)) break e;
    } else return throwReflection(ctx, "Array key not found");
    const ref = entry.ref orelse return NativeResult.scalar(.null);
    // a reference only this element binds is no reference, unless it holds
    // the very array (a directly self-referential one)
    const self_ref = ref.* == .array and ref.*.array == arr;
    if (@import("../runtime/value.zig").cellOf(ref).binders <= 1 and !self_ref) return NativeResult.scalar(.null);
    const obj = try ctx.createObject("ReflectionReference");
    try obj.set(ctx.allocator, "__cell", .{ .int = @intCast(@intFromPtr(@import("../runtime/value.zig").cellOf(ref))) });
    // the array keeps the reference alive while it is reflected
    try obj.set(ctx.allocator, "__array", .{ .array = arr });
    return NativeResult.borrowed(.{ .object = obj });
}

var reference_key: [16]u8 = undefined;
var reference_key_ready = false;

// sha1 of the reference's address and a per-process random key, as php
// hides the address
fn rrefGetId(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cell = this.get("__cell");
    if (cell != .int) return throwReflection(ctx, "Corrupted ReflectionReference object");
    if (!reference_key_ready) {
        @import("../platform.zig").io.random(&reference_key);
        reference_key_ready = true;
    }
    const address: usize = @intCast(cell.int);
    var sha = std.crypto.hash.Sha1.init(.{});
    sha.update(std.mem.asBytes(&address));
    sha.update(&reference_key);
    var digest: [20]u8 = undefined;
    sha.final(&digest);
    return try NativeResult.copyString(ctx.allocator, &digest);
}

fn rpConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const label = "ReflectionProperty::__construct";
    const class_arg = try zpp.objOrStr(ctx, label, args, 0, "class");
    const prop_name = try zpp.str(ctx, label, args, 1, "property");
    const class_name = try classArgument(ctx, class_arg);
    try ctx.vm.resolveClassDefaults(class_name);
    const found = visiblePropertyDef(ctx.vm, class_name, prop_name);
    if (found == null and !(args[0] == .object and findPropertyDef(ctx.vm, class_name, prop_name) == null and hasDynamicProperty(ctx.vm, args[0].object, prop_name))) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Property {s}::${s} does not exist", .{ class_name, prop_name });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    try setPropertyReflection(ctx, this, class_name, prop_name, found);
    return NativeResult.scalar(.null);
}

fn rpGetValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const label = "ReflectionProperty::getValue";
    const object = try zpp.optObject(ctx, label, args, 0, "object");
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (staticDeclaringClass(this)) |declaring| {
        const v = (try staticPropertyRaw(ctx, reflectedClass(this) orelse declaring, prop_name)) orelse .null;
        if (v == .undef) return uninitializedStatic(ctx, declaring, prop_name);
        return NativeResult.share(v);
    }
    const obj = object orelse return mustBeProvided(ctx, label);
    try checkPropertyInstance(ctx, this, obj);
    return readPropertyAs(ctx, obj, prop_name, reflectedClass(this) orelse obj.class_name);
}

// a static property's value with an uninitialized one left undef
fn staticPropertyRaw(ctx: *NativeContext, class_name: []const u8, prop_name: []const u8) RuntimeError!?Value {
    try ctx.vm.resolveClassDefaults(class_name);
    return ctx.vm.getStaticPropRaw(class_name, prop_name);
}

fn mustBeProvided(ctx: *NativeContext, label: []const u8) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "{s}(): Argument #1 ($object) must be provided for instance properties", .{label});
    defer ctx.allocator.free(msg);
    _ = try ctx.vm.throwBuiltinException("TypeError", msg);
    return error.RuntimeError;
}

fn uninitializedStatic(ctx: *NativeContext, declaring: []const u8, prop_name: []const u8) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "Typed static property {s}::${s} must not be accessed before initialization", .{ declaring, prop_name });
    defer ctx.allocator.free(msg);
    _ = try ctx.vm.throwBuiltinException("Error", msg);
    return error.RuntimeError;
}

// the class the reflector was made for (php's intern->ce)
fn reflectedClass(this: *PhpObject) ?[]const u8 {
    const v = this.get("__class");
    return if (v == .string) v.string.bytes() else null;
}

// the object must be an instance of the declaring class (the reflected class
// for a dynamic property)
fn checkPropertyInstance(ctx: *NativeContext, this: *PhpObject, obj: *PhpObject) RuntimeError!void {
    const dc = this.get("__declaring_class");
    const expected = if (dc == .string) dc.string.bytes() else reflectedClass(this) orelse return;
    if (!ctx.vm.isInstanceOf(obj.class_name, expected))
        return throwReflection(ctx, "Given object is not an instance of the class this property was declared in");
}

// php's read_property with EG(fake_scope) set to the reflected class: lazy
// initialization, get hooks, __get for an unset property, and the errors and
// warnings of a plain read
fn readPropertyAs(ctx: *NativeContext, obj_in: *PhpObject, prop_name: []const u8, scope: []const u8) RuntimeError!NativeResult {
    const vm = ctx.vm;
    const decl = vm.propertyDeclaration(obj_in.class_name, prop_name);
    const slot_scope = privateScopeFor(vm, obj_in.class_name, prop_name, scope) orelse decl.defining_class;
    try vm.triggerLazyProperty(obj_in, prop_name, slot_scope);
    const obj = obj_in.storage();
    if (vm.hasPropHook(obj.class_name, prop_name, .get) and !vm.inPropHook(obj, prop_name)) {
        if (try vm.callPropHook(obj, prop_name, .get, .null)) |hv| return NativeResult.share(hv);
    }
    const val = obj.rawForScope(prop_name, slot_scope);
    const slot_present = obj.slots != null and obj.getSlotIndexForScope(prop_name, slot_scope) != null;
    const present = !obj.isUnset(prop_name) and val != .undef and (val != .null or obj.properties.contains(prop_name) or slot_present);
    if (present) {
        if (val == .null and vm.typedPropForbidsNull(decl.type_str)) return uninitializedProperty(ctx, decl.defining_class, prop_name);
        return NativeResult.share(val);
    }
    // an uninitialized typed property is an error; only one that was unset
    // falls to __get
    if (decl.declared and decl.type_str.len > 0 and val == .undef and !obj.isUnset(prop_name)) return uninitializedProperty(ctx, decl.defining_class, prop_name);
    if (vm.magicApplies(obj, prop_name, .get)) {
        return NativeResult.share(try vm.callMagicProperty(obj, .get, prop_name, .null));
    }
    if (decl.declared and decl.type_str.len > 0) return uninitializedProperty(ctx, decl.defining_class, prop_name);
    const msg = try std.fmt.allocPrint(ctx.allocator, "Undefined property: {s}::${s}", .{ obj.class_name, prop_name });
    defer ctx.allocator.free(msg);
    try vm.emitWarning(msg);
    return NativeResult.scalar(.null);
}

fn uninitializedProperty(ctx: *NativeContext, declaring: []const u8, prop_name: []const u8) RuntimeError {
    const msg = try std.fmt.allocPrint(ctx.allocator, "Typed property {s}::${s} must not be accessed before initialization", .{ declaring, prop_name });
    defer ctx.allocator.free(msg);
    _ = try ctx.vm.throwBuiltinException("Error", msg);
    return error.RuntimeError;
}

// the scope's own private property of the name, which shadows any other
// declaration when read from that scope
fn privateScopeFor(vm: *VM, class_name: []const u8, prop_name: []const u8, scope: []const u8) ?[]const u8 {
    if (!vm.isInstanceOf(class_name, scope)) return null;
    const cls = vm.classes.get(scope) orelse return null;
    for (cls.properties.items) |prop| {
        if (prop.visibility == .private and std.mem.eql(u8, prop.name, prop_name)) return vm.declaredClassName(scope);
    }
    return null;
}

// the class of a static property this ReflectionProperty describes
fn staticDeclaringClass(this: *PhpObject) ?[]const u8 {
    const static_v = this.get("__is_static");
    if (static_v != .bool or !static_v.bool) return null;
    const dc = this.get("__declaring_class");
    return if (dc == .string) dc.string.bytes() else null;
}

fn rpSetValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return rpWrite(ctx, args, .value);
}
fn rpSetRawValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return rpWrite(ctx, args, .raw);
}
fn rpSetWithoutLazy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return rpWrite(ctx, args, .raw_without_lazy);
}

// getRawValue: a get hook is bypassed and the backing value read directly
fn rpGetRawValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const label = "ReflectionProperty::getRawValue";
    if (args[0] != .object) return zpp.typeError(ctx, label, 0, "object", "object", args[0]);
    const obj = args[0].object;
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const ce = reflectedClass(this) orelse obj.class_name;
    if (!ctx.vm.isInstanceOf(obj.class_name, ce)) return throwReflection(ctx, "Given object is not an instance of the class this property was declared in");
    if (staticDeclaringClass(this) != null) return throwReflection(ctx, "May not use getRawValue on static properties");
    if (!ctx.vm.hasPropHook(obj.class_name, prop_name, .get)) return readPropertyAs(ctx, obj, prop_name, ce);
    const decl = ctx.vm.propertyDeclaration(obj.class_name, prop_name);
    if (propertyIsVirtual(ctx.vm, decl.defining_class, prop_name)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Must not read from virtual property {s}::${s}", .{ decl.defining_class, prop_name });
        defer ctx.allocator.free(msg);
        _ = try ctx.vm.throwBuiltinException("Error", msg);
        return error.RuntimeError;
    }
    try ctx.vm.triggerLazyProperty(obj, prop_name, decl.defining_class);
    const val = obj.storage().rawForScope(prop_name, decl.defining_class);
    if (val == .undef or (val == .null and ctx.vm.typedPropForbidsNull(decl.type_str))) return uninitializedProperty(ctx, decl.defining_class, prop_name);
    return NativeResult.share(val);
}

fn propertyIsVirtual(vm: *VM, class_name: []const u8, prop_name: []const u8) bool {
    const found = findPropertyDef(vm, class_name, prop_name) orelse return false;
    return found.prop.is_virtual;
}

fn rpSkipLazy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    try checkLazyCompatible(ctx, this, "skipLazyInitialization");
    const name = this.get("name");
    const dc = this.get("__declaring_class");
    if (name != .string) return NativeResult.scalar(.null);
    const obj = args[0].object;
    if (obj.lazy) |state| {
        if (state.running or state.initializer == .null) return NativeResult.scalar(.null);
        if (obj.getSlotIndexForScope(name.string.bytes(), if (dc == .string) dc.string.bytes() else null)) |i| state.pending[i] = false;
        for (state.pending) |pending| {
            if (pending) return NativeResult.scalar(.null);
        }
        const initializer = state.initializer;
        state.initializer = .null;
        ctx.vm.releaseValue(initializer);
    }
    return NativeResult.scalar(.null);
}
fn rpIsLazy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const name = this.get("name");
    const dc = this.get("__declaring_class");
    return NativeResult.scalar(.{ .bool = name == .string and args[0].object.isLazySlot(name.string.bytes(), if (dc == .string) dc.string.bytes() else null) });
}
// reflection_property_check_lazy_compatible
fn checkLazyCompatible(ctx: *NativeContext, this: *PhpObject, method: []const u8) RuntimeError!void {
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else "";
    if (this.get("__dynamic") == .bool) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Can not use {s} on dynamic property {s}::${s}", .{ method, reflectedClass(this) orelse "", name });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    const dc = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else "";
    const kind: ?[]const u8 = if (staticDeclaringClass(this) != null) "static" else if (propertyIsVirtual(ctx.vm, dc, name)) "virtual" else null;
    if (kind) |k| {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Can not use {s} on {s} property {s}::${s}", .{ method, k, dc, name });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
}

const WriteMode = enum { value, raw, raw_without_lazy };

fn rpWrite(ctx: *NativeContext, args: []const Value, mode: WriteMode) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const skip = mode == .raw_without_lazy;
    const label = switch (mode) {
        .value => "ReflectionProperty::setValue",
        .raw => "ReflectionProperty::setRawValue",
        .raw_without_lazy => "ReflectionProperty::setRawValueWithoutLazyInitialization",
    };
    if (mode == .raw_without_lazy) try checkLazyCompatible(ctx, this, "setRawValueWithoutLazyInitialization");
    if (mode == .raw and staticDeclaringClass(this) != null) return throwReflection(ctx, "May not use setRawValue on static properties");
    if (mode == .value) if (staticDeclaringClass(this)) |declaring| {
        // php's setValue($value) and setValue($ignored, $value) forms
        const value = if (args.len == 1) args[0] else if (args.len >= 2) args[1] else {
            const msg = try std.fmt.allocPrint(ctx.allocator, "{s}() expects exactly 2 arguments, 0 given", .{label});
            defer ctx.allocator.free(msg);
            _ = try ctx.vm.throwBuiltinException("ArgumentCountError", msg);
            return error.RuntimeError;
        };
        if (args.len == 1) {
            try ctx.vm.raiseError(VM.E_DEPRECATED, "Calling ReflectionProperty::setValue() with a single argument is deprecated");
        } else if (args[0] != .null and args[0] != .object) {
            try ctx.vm.raiseError(VM.E_DEPRECATED, "Calling ReflectionProperty::setValue() with a 1st argument which is not null or an object is deprecated");
        }
        var v = value;
        const type_str = staticPropertyType(ctx.vm, declaring, prop_name);
        if (try ctx.vm.checkPropertyType(&v, type_str, declaring, prop_name)) return error.RuntimeError;
        try ctx.vm.setStaticPropValue(reflectedClass(this) orelse declaring, prop_name, v);
        return NativeResult.scalar(.null);
    };
    if (args.len < 2) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "{s}() expects exactly 2 arguments, {d} given", .{ label, args.len });
        defer ctx.allocator.free(msg);
        _ = try ctx.vm.throwBuiltinException("ArgumentCountError", msg);
        return error.RuntimeError;
    }
    if (args[0] != .object) return zpp.typeError(ctx, label, 0, "object", "object", args[0]);
    const target = args[0].object;
    const scope = reflectedClass(this) orelse target.class_name;
    const decl = ctx.vm.propertyDeclaration(target.class_name, prop_name);
    const slot_scope = privateScopeFor(ctx.vm, target.class_name, prop_name, scope) orelse decl.defining_class;
    if (mode != .value and ctx.vm.hasPropHook(target.class_name, prop_name, .set) and propertyIsVirtual(ctx.vm, decl.defining_class, prop_name)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Must not write to virtual property {s}::${s}", .{ decl.defining_class, prop_name });
        defer ctx.allocator.free(msg);
        _ = try ctx.vm.throwBuiltinException("Error", msg);
        return error.RuntimeError;
    }
    if (!skip) {
        try ctx.vm.triggerLazyProperty(target, prop_name, slot_scope);
        const obj = target.storage();
        if (mode == .value and ctx.vm.hasPropHook(obj.class_name, prop_name, .set) and !ctx.vm.inPropHook(obj, prop_name)) {
            if (try ctx.vm.callPropHook(obj, prop_name, .set, args[1])) |r| ctx.vm.releaseValue(r);
            return NativeResult.scalar(.null);
        }
        if (!decl.declared and ctx.vm.magicApplies(obj, prop_name, .set) and !obj.properties.contains(prop_name)) {
            const r = try ctx.vm.callMagicProperty(obj, .set, prop_name, args[1]);
            ctx.vm.releaseValue(r);
            return NativeResult.scalar(.null);
        }
    }
    const vr = ctx.vm.propertyDeclaration(slot_scope, prop_name);
    if (vr.is_readonly) {
        const current = target.rawForScope(prop_name, slot_scope);
        // a null slot counts as unset: a class declared by eval leaves an
        // uninitialized readonly property null rather than undef
        const initialized = current != .undef and current != .null and !target.isUnset(prop_name);
        // readonly is implicitly protected(set): any class of the hierarchy
        // may initialize it, none may modify it
        if (initialized) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot modify readonly property {s}::${s}", .{ target.class_name, prop_name });
            defer ctx.allocator.free(msg);
            _ = try ctx.vm.throwBuiltinException("Error", msg);
            return error.RuntimeError;
        }
    }
    var value = args[1];
    if (try ctx.vm.checkPropertyType(&value, vr.type_str, vr.defining_class, prop_name)) return error.RuntimeError;
    try target.setForScope(ctx.allocator, prop_name, value, slot_scope);
    if (skip) _ = try rpSkipLazy(ctx, args);
    return NativeResult.scalar(.null);
}

// the declared type of a static property, searched up from its class
fn staticPropertyType(vm: *VM, class_name: []const u8, prop_name: []const u8) []const u8 {
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        const cls = vm.classes.get(cn) orelse break;
        if (cls.static_prop_types.get(prop_name)) |t| return t;
        if (cls.static_props.contains(prop_name)) return "";
        current = cls.parent;
    }
    return "";
}

fn rpropGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

// the type a write must satisfy: never for a get-only virtual property, the
// set hook's parameter type, else the property's
fn rpropGetSettableType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const dc = this.get("__declaring_class");
    const name = this.get("name");
    if (dc != .string or name != .string) return NativeResult.scalar(.null);
    const set_hook = lookupPropertyHook(ctx, "set");
    if (set_hook == null and lookupPropertyHook(ctx, "get") != null and propertyIsVirtual(ctx.vm, dc.string.bytes(), name.string.bytes()))
        return NativeResult.borrowed(.{ .object = try createTypeObj(ctx, "never", false, null) });
    if (set_hook) |hook| {
        var buf: [512]u8 = undefined;
        const key = class_names.memberKey(&buf, hook.declaring, hook.info.name);
        if (methodTypeInfo(ctx.vm, key)) |ti| if (ti.param_types.len > 0 and ti.param_types[0].len > 0)
            return NativeResult.borrowed(.{ .object = try createTypeObj(ctx, ti.param_types[0], false, hook.declaring) });
    }
    return rpropGetType(ctx, &.{});
}

fn rpropGetType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const dc_v = this.get("__declaring_class");
    if (dc_v != .string) return NativeResult.scalar(.null);
    const class_name = dc_v.string.bytes();
    const prop_name_v = this.get("name");
    if (prop_name_v != .string) return NativeResult.scalar(.null);
    const prop_name = prop_name_v.string.bytes();

    // walk the class chain looking for a declared property with a type. each
    // ClassDef.PropertyDef carries the source-form type string (set at class
    // load time by the bytecode reader)
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            for (cls.properties.items) |p| {
                if (std.mem.eql(u8, p.name, prop_name)) {
                    if (p.type_str.len > 0) {
                        const obj = try createTypeObj(ctx, p.type_str, false, cn);
                        return NativeResult.borrowed(.{ .object = obj });
                    }
                    return NativeResult.scalar(.null);
                }
            }
            if (cls.static_prop_types.get(prop_name)) |type_str| {
                const obj = try createTypeObj(ctx, type_str, false, cn);
                return NativeResult.borrowed(.{ .object = obj });
            }
            current = cls.parent;
        } else break;
    }
    return NativeResult.scalar(.null);
}

fn makeReflectionType(ctx: *NativeContext, type_str: []const u8) RuntimeError!Value {
    var name = type_str;
    var allows_null = false;
    if (name.len > 0 and name[0] == '?') {
        allows_null = true;
        name = name[1..];
    }
    // normalize "T|null" / "null|T" to nullable named type when only one non-null part remains
    if (std.mem.indexOfScalar(u8, name, '|')) |_| {
        var has_null = false;
        var non_null_count: usize = 0;
        var only_non_null: []const u8 = "";
        var it = std.mem.splitScalar(u8, name, '|');
        while (it.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " ");
            if (std.ascii.eqlIgnoreCase(trimmed, "null")) {
                has_null = true;
            } else {
                non_null_count += 1;
                only_non_null = trimmed;
            }
        }
        if (has_null and non_null_count == 1) {
            name = only_non_null;
            allows_null = true;
        }
    }
    // union/intersection types not modeled as ReflectionUnionType yet - return
    // the first segment so the most common case (single named type) works
    if (std.mem.indexOfAny(u8, name, "|&")) |sep| name = name[0..sep];
    const obj = try ctx.createObject("ReflectionNamedType");
    const dup = try ctx.allocator.dupe(u8, name);
    defer ctx.allocator.free(dup);
    try obj.setCopiedString(ctx.allocator, "__type_name", dup);
    try obj.set(ctx.allocator, "__nullable", .{ .bool = allows_null or std.mem.eql(u8, name, "mixed") or std.mem.eql(u8, name, "null") });
    try obj.set(ctx.allocator, "__is_builtin", .{ .bool = isBuiltinTypeName(name) });
    return .{ .object = obj };
}

fn isBuiltinTypeName(name: []const u8) bool {
    const builtins = [_][]const u8{ "int", "float", "string", "bool", "array", "object", "callable", "iterable", "void", "mixed", "never", "null", "false", "true", "self", "static", "parent" };
    for (builtins) |b| if (std.mem.eql(u8, b, name)) return true;
    return false;
}

fn rpropIsPublic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const vis = this.get("__visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 0 });
}

fn rpropIsProtected(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("__visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 1 });
}

fn rpropIsPrivate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("__visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 2 });
}

fn rpropIsPrivateSet(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("__visibility");
    const set_vis = this.get("__set_visibility");
    const vis_val = if (vis == .int) vis.int else 0;
    const set_vis_val = if (set_vis == .int) set_vis.int else vis_val;
    return NativeResult.scalar(.{ .bool = set_vis_val == 2 and vis_val != 2 });
}

fn rpropIsProtectedSet(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("__visibility");
    const set_vis = this.get("__set_visibility");
    const has_set_vis = this.get("__has_set_visibility");
    const ro = this.get("__is_readonly");
    const is_ro = ro == .bool and ro.bool;
    const has_explicit_set = has_set_vis == .bool and has_set_vis.bool;
    const vis_val = if (vis == .int) vis.int else 0;
    const set_vis_val = if (set_vis == .int) set_vis.int else vis_val;

    return NativeResult.scalar(.{
        .bool = (set_vis_val == 1 and vis_val == 0) or
            (is_ro and vis_val == 0 and !has_explicit_set),
    });
}
fn rpropIsFinal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });

    const final_v = this.get("__is_final");
    const is_explicit_final = final_v == .bool and final_v.bool;
    if (is_explicit_final) return NativeResult.scalar(.{ .bool = true });

    const vis = this.get("__visibility");
    const set_vis = this.get("__set_visibility");
    const has_set_vis = this.get("__has_set_visibility");
    const vis_val = if (vis == .int) vis.int else 0;
    const set_vis_val = if (set_vis == .int) set_vis.int else vis_val;
    const has_explicit_set = has_set_vis == .bool and has_set_vis.bool;

    // PHP 8.4 only treats asymmetric private(set) as implicitly final.
    // Symmetric `private private(set)` and private readonly remain non-final.
    const implicit_private_set_final =
        has_explicit_set and set_vis_val == 2 and vis_val != 2;

    return NativeResult.scalar(.{ .bool = implicit_private_set_final });
}

fn rpropIsAbstract(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    for ([_][]const u8{ "get", "set" }) |kind| {
        if (lookupPropertyHook(ctx, kind)) |hook| {
            if (hook.info.is_abstract) return NativeResult.scalar(.{ .bool = true });
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rpropGetDefaultValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const has_default = this.get("__has_default");
    if (has_default != .bool or !has_default.bool) {
        try ctx.vm.raiseError(VM.E_DEPRECATED, "ReflectionProperty::getDefaultValue() for a property without a default value is deprecated, use ReflectionProperty::hasDefaultValue() to check if the default value exists");
        return NativeResult.scalar(.null);
    }
    return NativeResult.share(this.get("__default_value"));
}

fn rpropHasDefaultValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const has_default = this.get("__has_default");
    return NativeResult.scalar(.{ .bool = has_default == .bool and has_default.bool });
}

fn rpropIsInitialized(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const label = "ReflectionProperty::isInitialized";
    const object = try zpp.optObject(ctx, label, args, 0, "object");
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (staticDeclaringClass(this)) |declaring| {
        const v = (try staticPropertyRaw(ctx, reflectedClass(this) orelse declaring, prop_name)) orelse .undef;
        return NativeResult.scalar(.{ .bool = v != .undef });
    }
    const obj_in = object orelse return mustBeProvided(ctx, label);
    try checkPropertyInstance(ctx, this, obj_in);
    const scope = reflectedClass(this) orelse obj_in.class_name;
    const decl = ctx.vm.propertyDeclaration(obj_in.class_name, prop_name);
    const slot_scope = privateScopeFor(ctx.vm, obj_in.class_name, prop_name, scope) orelse decl.defining_class;
    try ctx.vm.triggerLazyProperty(obj_in, prop_name, slot_scope);
    const obj = obj_in.storage();
    // has_property(ZEND_PROPERTY_EXISTS), which never calls __isset: a
    // virtual property exists
    if (decl.declared and propertyIsVirtual(ctx.vm, decl.defining_class, prop_name)) return NativeResult.scalar(.{ .bool = true });
    const val = obj.rawForScope(prop_name, slot_scope);
    const slot_present = obj.slots != null and obj.getSlotIndexForScope(prop_name, slot_scope) != null;
    if (obj.isUnset(prop_name) or val == .undef or !(val != .null or obj.properties.contains(prop_name) or slot_present)) {
        return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = !(val == .null and ctx.vm.typedPropForbidsNull(decl.type_str)) });
}

fn rpropGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else reflectedClass(this) orelse return NativeResult.scalar(.null);

    const obj = try classObject(ctx, declaring);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rpropIsDefault(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = this.get("__dynamic") != .bool });
}

fn rpropIsDynamic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = this.get("__dynamic") == .bool });
}

// the property's key in the object's property table: (array)'s mangled name
fn rpropGetMangledName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = this.get("name");
    if (name != .string) return NativeResult.scalar(.null);
    const dc = this.get("__declaring_class");
    const vis = this.get("__visibility");
    if (dc != .string or vis != .int or vis.int == @backingInt(ClassDef.Visibility.public)) return NativeResult.share(name);
    const text = if (vis.int == @backingInt(ClassDef.Visibility.protected))
        try std.fmt.allocPrint(ctx.allocator, "\x00*\x00{s}", .{name.string.bytes()})
    else
        try std.fmt.allocPrint(ctx.allocator, "\x00{s}\x00{s}", .{ dc.string.bytes(), name.string.bytes() });
    defer ctx.allocator.free(text);
    return try NativeResult.copyString(ctx.allocator, text);
}

fn rpropIsReadOnly(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = this.get("__is_readonly");
    return NativeResult.scalar(.{ .bool = v == .bool and v.bool });
}

fn rpropIsStatic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = this.get("__is_static");
    return NativeResult.scalar(.{ .bool = v == .bool and v.bool });
}

fn rpropIsPromoted(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // a property is promoted iff it appears as a constructor parameter that
    // had a visibility modifier (zphp tracks promotion on the constructor's
    // params; detect it by matching the property name against the ctor's
    // param list)
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("__declaring_class") == .string)
        this.get("__declaring_class").string.bytes()
    else if (this.get("class") == .string)
        this.get("class").string.bytes()
    else
        return NativeResult.scalar(.{ .bool = false });
    const prop_name_v = this.get("name");
    if (prop_name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const prop_name = prop_name_v.string.bytes();

    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    for (cls.properties.items) |prop| {
        if (std.mem.eql(u8, prop.name, prop_name) and prop.is_promoted) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rpropHasType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const type_value = (try rpropGetType(ctx, &.{})).value;
    if (type_value == .string) type_value.string.release();
    return NativeResult.scalar(.{ .bool = type_value != .null });
}

fn rpropGetModifiers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const vis = this.get("__visibility");
    const vis_val = if (vis == .int) vis.int else 0;

    var mods: i64 = switch (vis_val) {
        1 => 2, // IS_PROTECTED
        2 => 4, // IS_PRIVATE
        else => 1, // IS_PUBLIC
    };

    const st = this.get("__is_static");
    if (st == .bool and st.bool) mods |= 16;

    const ro = this.get("__is_readonly");
    const is_ro = ro == .bool and ro.bool;
    if (is_ro) mods |= 128;

    const set_vis = this.get("__set_visibility");
    const has_set_vis = this.get("__has_set_visibility");
    const set_vis_val = if (set_vis == .int) set_vis.int else vis_val;
    const has_explicit_set = has_set_vis == .bool and has_set_vis.bool;

    const final_v = this.get("__is_final");
    const is_explicit_final = final_v == .bool and final_v.bool;
    // Match PHP 8.4: only asymmetric private(set) contributes IS_FINAL.
    const implicit_private_set_final =
        has_explicit_set and set_vis_val == 2 and vis_val != 2;
    if (is_explicit_final or implicit_private_set_final) mods |= 32;

    const is_asym_private_set =
        has_explicit_set and set_vis_val == 2 and vis_val != 2;
    if (is_asym_private_set) mods |= 4096;

    const is_asym_prot_set =
        (has_explicit_set and set_vis_val == 1 and vis_val == 0) or
        (is_ro and vis_val == 0 and !has_explicit_set);
    if (is_asym_prot_set) mods |= 2048;

    // a property with an abstract hook is abstract
    if ((try rpropIsAbstract(ctx, &.{})).value.bool) mods |= 64;

    return NativeResult.scalar(.{ .int = mods });
}

fn rpropGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try checkAttributeFilter(ctx, args, "ReflectionProperty");
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const attrs = propertyAttributes(ctx.vm, declaring, prop_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 8, flags, declaring);
}

// a property's attributes, read from the trait that declared it when the
// class took the property from one
fn propertyAttributes(vm: *VM, class_name: []const u8, prop_name: []const u8) ?[]const AttributeDef {
    const cls = vm.classes.get(class_name) orelse return null;
    if (cls.property_attributes.get(prop_name)) |attrs| return attrs;
    const trait = cls.trait_property_origins.get(prop_name) orelse return null;
    return propertyAttributes(vm, trait, prop_name);
}

fn rpropGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const dc_v = this.get("__declaring_class");
    if (dc_v != .string) return NativeResult.scalar(.{ .bool = false });
    const prop_name_v = this.get("name");
    if (prop_name_v != .string) return NativeResult.scalar(.{ .bool = false });
    if (staticDeclaringClass(this)) |declaring| {
        const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.{ .bool = false });
        const doc = cls.static_prop_docs.get(prop_name_v.string.bytes()) orelse "";
        if (doc.len == 0) return NativeResult.scalar(.{ .bool = false });
        return try NativeResult.copyString(ctx.allocator, doc);
    }
    var current: ?[]const u8 = dc_v.string.bytes();
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            for (cls.properties.items) |p| {
                if (std.mem.eql(u8, p.name, prop_name_v.string.bytes())) {
                    if (p.doc_comment.len == 0) return NativeResult.scalar(.{ .bool = false });
                    return try NativeResult.copyString(ctx.allocator, p.doc_comment);
                }
            }
            current = cls.parent;
        } else break;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rpropIsVirtual(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const dc = this.get("__declaring_class");
    const name = this.get("name");
    if (dc == .string and name == .string) {
        if (ctx.vm.classes.get(dc.string.bytes())) |cls| {
            for (cls.properties.items) |p| {
                if (std.mem.eql(u8, p.name, name.string.bytes())) return NativeResult.scalar(.{ .bool = p.is_virtual });
            }
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rmInvoke(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return methodInvoke(ctx, args, true);
}

fn rmInvokeArgs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return methodInvoke(ctx, args, false);
}

// php's reflection_method_invoke: the reflected method itself is called (no
// override, no visibility check), static methods ignore the object
fn methodInvoke(ctx: *NativeContext, args: []const Value, variadic: bool) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const label = if (variadic) "ReflectionMethod::invoke" else "ReflectionMethod::invokeArgs";
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.null);
    if (this.get("__closure") != .null) {
        const target = if (args.len > 0) args[0] else Value.null;
        if (!isClosureValue(target)) {
            if (target != .null and target != .object) return zpp.typeError(ctx, label, 0, "object", "?object", target);
            return throwReflection(ctx, "Given object is not an instance of the class this method was declared in");
        }
        const named: ?*PhpArray = if (variadic) null else try zpp.array(ctx, label, args, 1, "args");
        const rest = if (variadic and args.len > 1) args[1..] else &[_]Value{};
        const key = target.closureName() orelse "";
        var bound = try bindArguments(ctx, key, "{closure}", rest, named);
        defer bound.deinit(ctx.allocator);
        return NativeResult.share(try ctx.invokeCallable(target, bound.list.items));
    }
    if (methodIsAbstract(ctx.vm, this, method_name, declaring)) return throwReflectionFmt(ctx, "Trying to invoke abstract method {s}::{s}()", .{ declaring, method_name });
    var object: ?*PhpObject = null;
    var closure_target: ?Value = null;
    if (args.len > 0 and args[0].closureName() != null) closure_target = args[0] else object = try zpp.optObject(ctx, label, args, 0, "object");
    const named: ?*PhpArray = if (variadic) null else try zpp.array(ctx, label, args, 1, "args");
    const is_static = this.get("__is_static") == .bool and this.get("__is_static").bool;
    if (!is_static) {
        if (closure_target) |closure| {
            const rest = if (variadic) args[1..] else &[_]Value{};
            var bound = try bindArguments(ctx, closure.closureName().?, "{closure}", rest, named);
            defer bound.deinit(ctx.allocator);
            return NativeResult.share(try ctx.invokeCallable(closure, bound.list.items));
        }
        const obj = object orelse return throwReflectionFmt(ctx, "Trying to invoke non static method {s}::{s}() without an object", .{ declaring, method_name });
        if (!ctx.vm.isInstanceOf(obj.class_name, declaring)) return throwReflection(ctx, "Given object is not an instance of the class this method was declared in");
    }
    const guard_count = ctx.vm.prop_hook_guard.items.len;
    defer ctx.vm.prop_hook_guard.shrinkRetainingCapacity(guard_count);
    if (this.get("__hook_property") == .string) if (object) |obj| {
        try ctx.vm.prop_hook_guard.append(ctx.allocator, .{ .obj_ptr = @intFromPtr(obj), .prop_name = this.get("__hook_property").string.bytes() });
    };
    var buf: [256]u8 = undefined;
    const full = class_names.memberKey(&buf, declaring, method_name);
    const owned_key = try ctx.vm.internName(full);
    const positional = if (variadic and args.len > 1) args[1..] else &[_]Value{};
    var bound = try bindArguments(ctx, owned_key, owned_key, positional, named);
    defer bound.deinit(ctx.allocator);
    const outer = ctx.vm.native_caller;
    ctx.vm.native_caller = .{ .name = label, .frames = ctx.vm.frame_count };
    defer ctx.vm.native_caller = outer;
    if (!is_static) return NativeResult.share(try ctx.vm.callMethodAs(object.?, method_name, owned_key, bound.list.items));
    const called = reflectedClass(this) orelse declaring;
    return NativeResult.share(try ctx.vm.callByNameAs(owned_key, bound.list.items, called));
}

fn methodIsAbstract(vm: *VM, this: *PhpObject, method_name: []const u8, declaring: []const u8) bool {
    _ = this;
    if (vm.interfaces.contains(declaring)) return true;
    if (vm.classes.get(declaring)) |cls| {
        if (cls.methods.get(method_name)) |m| if (m.is_abstract) return true;
    }
    var buf: [256]u8 = undefined;
    const key = class_names.memberKey(&buf, declaring, method_name);
    return vm.functions.get(key) == null and vm.native_fns.get(key) == null;
}

fn rmGetClosure(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const label = "ReflectionMethod::getClosure";
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.null);
    const target: Value = if (args.len > 0) args[0] else .null;
    // a closure's own __invoke is the closure
    if (this.get("__closure") != .null and isClosureValue(target)) return NativeResult.share(target);
    const object: ?*PhpObject = if (isClosureValue(target)) null else try zpp.optObject(ctx, label, args, 0, "object");
    const is_static = this.get("__is_static") == .bool and this.get("__is_static").bool;
    var buf: [256]u8 = undefined;
    const full = try ctx.vm.internName(class_names.memberKey(&buf, declaring, method_name));
    if (is_static) return wrapCallableClosure(ctx, .{ .string = Value.String.borrowed(full) });
    const obj = object orelse {
        _ = try ctx.vm.throwBuiltinException("ValueError", "ReflectionMethod::getClosure(): Argument #1 ($object) cannot be null for non-static methods");
        return error.RuntimeError;
    };
    if (!ctx.vm.isInstanceOf(obj.class_name, declaring)) return throwReflection(ctx, "Given object is not an instance of the class this method was declared in");
    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, .{ .object = obj });
    // the method itself, named plainly when the object's class resolves
    // the name to it
    const resolved = findDeclaringClass(ctx.vm, obj.class_name, method_name);
    const callable_name = if (std.ascii.eqlIgnoreCase(resolved, declaring)) try ctx.vm.internName(method_name) else full;
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(callable_name) });
    return wrapCallableClosure(ctx, .{ .array = arr });
}

// a closure reflects as itself; a function as a closure calling it
fn rfGetClosure(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const closure = this.get("__closure");
    if (closure == .object) return NativeResult.share(closure);
    const name = this.get("name");
    if (name != .string) return NativeResult.scalar(.null);
    return wrapCallableClosure(ctx, name);
}

fn rmIsAbstract(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .bool = false });
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });

    if (ctx.vm.interfaces.contains(declaring)) return NativeResult.scalar(.{ .bool = true });

    if (ctx.vm.classes.get(declaring)) |cls| {
        if (cls.methods.get(method_name)) |m| {
            if (m.is_abstract) return NativeResult.scalar(.{ .bool = true });
        }
    }

    var buf: [256]u8 = undefined;
    const key = methodKey(this, &buf, declaring, method_name);
    if (ctx.vm.functions.get(key) == null and ctx.vm.native_fns.get(key) == null) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = false });
}

fn rmIsFinal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .bool = false });
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.{ .bool = false });
    const m = cls.methods.get(method_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = m.is_final });
}

fn rmFullName(ctx: *NativeContext) ?[]const u8 {
    const this = getThis(ctx) orelse return null;
    const method_name = methodLookupName(this) orelse return null;
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return null;
    var buf: [256]u8 = undefined;
    const key = methodKey(this, &buf, declaring, method_name);
    const owned = Value.String.create(ctx.allocator, key) catch return null;
    return ctx.vm.transientOwned(owned).bytes();
}

fn rmIsVariadic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const key = rmFullName(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(key) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.is_variadic });
}

fn rmReturnsReference(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const key = rmFullName(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(key) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.returns_ref });
}

fn rmIsGenerator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const key = rmFullName(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(key) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.is_generator });
}

fn rmGetModifiers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .int = 0 });
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.{ .int = 0 });
    // an interface's methods are public and abstract
    const in_interface = ctx.vm.interfaces.contains(declaring);
    const interface_bits: i64 = if (in_interface) 64 else 0;
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.{ .int = if (in_interface) 65 else 0 });
    const info = cls.methods.get(method_name) orelse return NativeResult.scalar(.{ .int = if (in_interface) 65 else 0 });
    return NativeResult.scalar(.{ .int = interface_bits | if (this.get("__hook_method") == .string) (methodModifiers(info) & ~@as(i64, 7)) | 1 else methodModifiers(info) });
}

fn nextName(n: *usize) usize {
    n.* += 1;
    return n.* - 1;
}

fn reflectionGetModifierNames(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const m = args[0].int;
    const arr = try ctx.createArray();
    // php's order; a visibility is named only when exactly one is set
    var names: [8][]const u8 = undefined;
    var n: usize = 0;
    if ((m & 0x40) != 0) names[nextName(&n)] = "abstract";
    if ((m & 0x20) != 0) names[nextName(&n)] = "final";
    if ((m & 0x200) != 0) names[nextName(&n)] = "virtual";
    switch (m & 0x7) {
        1 => names[nextName(&n)] = "public",
        2 => names[nextName(&n)] = "protected",
        4 => names[nextName(&n)] = "private",
        else => {},
    }
    switch (m & 0x1800) {
        0x800 => names[nextName(&n)] = "protected(set)",
        0x1000 => names[nextName(&n)] = "private(set)",
        else => {},
    }
    if ((m & 0x10) != 0) names[nextName(&n)] = "static";
    if ((m & (0x80 | 0x10000)) != 0) names[nextName(&n)] = "readonly";
    for (names[0..n]) |name| try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(name) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn rmGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try checkAttributeFilter(ctx, args, "ReflectionFunctionAbstract");
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const method_name = methodLookupName(this) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const attrs = methodAttributes(ctx.vm, declaring, method_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 4, flags, declaring);
}

// a method's attributes, read from the trait that declared it when the
// class took the method from one
fn methodAttributes(vm: *VM, class_name: []const u8, method_name: []const u8) ?[]const AttributeDef {
    if (vm.classes.get(class_name)) |cls| {
        if (cls.method_attributes.get(method_name)) |attrs| return attrs;
    }
    var key_buf: [512]u8 = undefined;
    const key = class_names.memberKey(&key_buf, class_name, method_name);
    const func = vm.functions.get(key) orelse return null;
    const code_name = if (func.trait_origin.len > 0) func.trait_origin else func.name;
    const sep = std.mem.indexOf(u8, code_name, "::") orelse return null;
    const origin = code_name[0..sep];
    if (std.mem.eql(u8, origin, class_name) or !vm.traits.contains(origin)) return null;
    const trait = vm.classes.get(origin) orelse return null;
    return trait.method_attributes.get(code_name[sep + 2 ..]);
}

fn rpIsPromoted(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    // promoted iff declaring method is __construct AND the class has a
    // matching property that is itself flagged as promoted. previously we
    // returned true whenever any same-named property existed, which mis-
    // classified plain '?string $name = null' params as promoted whenever
    // the class happened to declare a separate '$name' property
    const method_v = this.get("__method_name");
    if (method_v != .string or !std.mem.eql(u8, method_v.string.bytes(), "__construct")) return NativeResult.scalar(.{ .bool = false });
    const class_v = this.get("__declaring_class");
    if (class_v != .string) return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.getPtr(class_v.string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    for (cls.properties.items) |prop| {
        if (std.mem.eql(u8, prop.name, name_v.string.bytes())) return NativeResult.scalar(.{ .bool = prop.is_promoted });
    }
    return NativeResult.scalar(.{ .bool = false });
}

// isArray and isCallable: the parameter's type is that one type, perhaps
// nullable
fn rpTypeIs(ctx: *NativeContext, want: []const u8) bool {
    const this = getThis(ctx) orelse return false;
    const type_val = this.get("__type_name");
    if (type_val != .string) return false;
    var t = std.mem.trimStart(u8, type_val.string.bytes(), "?");
    if (std.mem.indexOfScalar(u8, t, '|')) |_| {
        var it = std.mem.splitScalar(u8, t, '|');
        var other: ?[]const u8 = null;
        var count: usize = 0;
        while (it.next()) |part| {
            if (std.ascii.eqlIgnoreCase(part, "null")) continue;
            other = part;
            count += 1;
        }
        if (count != 1) return false;
        t = other.?;
    }
    return std.ascii.eqlIgnoreCase(t, want);
}

fn rpIsArray(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = rpTypeIs(ctx, "array") });
}

fn rpIsCallable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = rpTypeIs(ctx, "callable") });
}

fn rpGetClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const type_val = this.get("__type_name");
    if (type_val != .string) return NativeResult.scalar(.null);
    const type_name = std.mem.trimStart(u8, type_val.string.bytes(), "?");
    if (type_name.len == 0 or std.mem.indexOfAny(u8, type_name, "|&(") != null or isBuiltinType(type_name)) return NativeResult.scalar(.null);
    const is_self = std.ascii.eqlIgnoreCase(type_name, "self");
    const is_parent = std.ascii.eqlIgnoreCase(type_name, "parent");
    if (is_self or is_parent) {
        const what = if (is_self) "self" else "parent";
        const scope = parameterScope(ctx, this) orelse return throwReflectionFmt(ctx, "Parameter uses \"{s}\" as type but function is not a class member", .{what});
        if (is_self) return NativeResult.borrowed(.{ .object = try classObject(ctx, scope) });
        const parent = if (ctx.vm.classes.get(scope)) |cd| cd.parent else null;
        const p = parent orelse return throwReflection(ctx, "Parameter uses \"parent\" as type although class does not have a parent");
        return NativeResult.borrowed(.{ .object = try classObject(ctx, p) });
    }
    const found = (try lookupClass(ctx, type_name)) orelse return throwReflectionFmt(ctx, "Class \"{s}\" does not exist", .{type_name});
    return NativeResult.borrowed(.{ .object = try classObject(ctx, found) });
}

// the class scope of a parameter's function: a method's class, a closure's
// scope
fn parameterScope(ctx: *NativeContext, this: *PhpObject) ?[]const u8 {
    if (this.get("__declaring_class") == .string) return this.get("__declaring_class").string.bytes();
    if (this.get("__closure").closureName()) |instance| return ctx.vm.closureScopeByName(instance);
    const func = this.get("__function");
    if (func == .string and std.mem.startsWith(u8, func.string.bytes(), "__closure_")) return ctx.vm.closureScopeByName(func.string.bytes());
    return null;
}

fn attributeConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const flags = if (args.len > 0 and args[0] == .int) args[0] else Value{ .int = 127 };
    try this.set(ctx.allocator, "flags", flags);
    return NativeResult.scalar(.null);
}

fn raConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return throwReflection(ctx, "Cannot directly instantiate ReflectionAttribute");
}

fn raGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn raGetArguments(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const args = this.get("__arguments");
    if (args == .array) return NativeResult.borrowed(.{ .array = try resolvedArguments(ctx, this, args.array) });
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

// the attribute's arguments with any that were deferred at declaration
// resolved now, as php evaluates them when asked; one that still cannot be
// resolved raises php's error here
fn resolvedArguments(ctx: *NativeContext, this: *PhpObject, stored: *PhpArray) RuntimeError!*PhpArray {
    const scope = this.get("__scope");
    const out = try ctx.createArray();
    for (stored.entries.items) |entry| {
        const value = try ctx.vm.attributeArgumentValue(entry.value, if (scope == .string) scope.string.bytes() else "");
        try out.set(ctx.allocator, entry.key, value);
    }
    return out;
}

fn targetName(t: i64) []const u8 {
    return switch (t) {
        1 => "class",
        2 => "function",
        4 => "method",
        8 => "property",
        16 => "class constant",
        32 => "parameter",
        64 => "constant",
        else => "this declaration",
    };
}

fn isAttributeClass(vm: *VM, class_name: []const u8) bool {
    if (std.mem.eql(u8, class_name, "Attribute")) return true;
    const cls = vm.classes.get(class_name) orelse return false;
    for (cls.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.name, "Attribute")) return true;
    }
    return false;
}

fn getAttributeFlags(vm: *VM, class_name: []const u8) RuntimeError!i64 {
    const cls = vm.classes.get(class_name) orelse return 127;
    for (cls.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.name, "Attribute")) {
            if (attr.args.len == 0) return 127; // TARGET_ALL
            // php's zend_attribute_attribute_get_flags
            const flags = try vm.attributeArgumentValue(attr.args[0], class_name);
            if (flags != .int) {
                const msg = try std.fmt.allocPrint(vm.allocator, "Attribute::__construct(): Argument #1 ($flags) must be of type int, {s} given", .{flags.valueName()});
                defer vm.allocator.free(msg);
                try vm.setPendingException("Error", msg);
                return error.RuntimeError;
            }
            if (flags.int & ~@as(i64, 255) != 0) {
                try vm.setPendingException("Error", "Invalid attribute flags specified");
                return error.RuntimeError;
            }
            return flags.int;
        }
    }
    return 127;
}

fn raNewInstance(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name_val = this.get("name");
    if (name_val != .string) return NativeResult.scalar(.null);
    const attr_name = name_val.string.bytes();

    if (!ctx.vm.classes.contains(attr_name)) {
        try ctx.vm.tryAutoload(attr_name);
    }

    if (!ctx.vm.classes.contains(attr_name)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Attribute class \"{s}\" not found", .{attr_name}) catch return error.OutOfMemory;
        defer ctx.allocator.free(msg);
        _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
        return error.RuntimeError;
    }

    if (!isAttributeClass(ctx.vm, attr_name)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Attempting to use non-attribute class \"{s}\" as attribute", .{attr_name}) catch return error.OutOfMemory;
        defer ctx.allocator.free(msg);
        _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
        return error.RuntimeError;
    }

    const target_val = this.get("__target");
    if (target_val == .int) {
        const target = target_val.int;
        const flags = try getAttributeFlags(ctx.vm, attr_name);
        if (flags != 127 and (flags & target) == 0) {
            const used = targetName(target);
            var allowed_buf: std.ArrayListUnmanaged(u8) = .empty;
            defer allowed_buf.deinit(ctx.allocator);
            const bits = [_]i64{ 1, 2, 4, 8, 16, 32, 64 };
            for (bits) |b| {
                if ((flags & b) != 0) {
                    if (allowed_buf.items.len > 0) try allowed_buf.appendSlice(ctx.allocator, ", ");
                    try allowed_buf.appendSlice(ctx.allocator, targetName(b));
                }
            }
            const msg = std.fmt.allocPrint(ctx.allocator, "Attribute \"{s}\" cannot target {s} (allowed targets: {s})", .{ attr_name, used, allowed_buf.items }) catch return error.OutOfMemory;
            defer ctx.allocator.free(msg);
            _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
            return error.RuntimeError;
        }
    }

    const is_repeated_val = this.get("__is_repeated");
    if (is_repeated_val == .bool and is_repeated_val.bool) {
        const flags = try getAttributeFlags(ctx.vm, attr_name);
        if ((flags & 128) == 0) {
            const msg = std.fmt.allocPrint(ctx.allocator, "Attribute \"{s}\" must not be repeated", .{attr_name}) catch return error.OutOfMemory;
            defer ctx.allocator.free(msg);
            _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
            return error.RuntimeError;
        }
    }

    // the attribute is built from no class's scope
    if (ctx.vm.hasMethod(attr_name, "__construct")) {
        const ctor = ctx.vm.findMethodVisibility(attr_name, "__construct");
        if (ctor.visibility != .public) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Call to {s} {s}::__construct() from global scope", .{ if (ctor.visibility == .private) "private" else "protected", ctor.defining_class });
            defer ctx.allocator.free(msg);
            try ctx.vm.setPendingException("Error", msg);
            return error.RuntimeError;
        }
    }
    const obj = try ctx.createObject(attr_name);
    const stored_args = this.get("__arguments");
    const args_val: Value = if (stored_args == .array) .{ .array = try resolvedArguments(ctx, this, stored_args.array) } else stored_args;
    // without a constructor php drops positional arguments and refuses
    // named ones
    const ctor = findConstructor(ctx.vm, attr_name) orelse {
        if (args_val == .array) for (args_val.array.entries.items) |entry| if (entry.key == .string) {
            return raiseError(ctx, "Error", "Unknown named parameter ${s}", .{entry.key.string.bytes()});
        };
        return NativeResult.borrowed(.{ .object = obj });
    };
    // the arguments bind as any call from internal code does (named ones
    // placed on the constructor's parameters, skipped ones defaulted)
    var key_buf: [256]u8 = undefined;
    const key = try ctx.vm.internName(class_names.memberKey(&key_buf, ctor.declaring, ctor.name));
    var bound = try bindArguments(ctx, key, key, &.{}, if (args_val == .array) args_val.array else null);
    defer bound.deinit(ctx.allocator);
    const outer = ctx.vm.native_caller;
    ctx.vm.native_caller = .{ .name = "ReflectionAttribute::newInstance", .frames = ctx.vm.frame_count };
    defer ctx.vm.native_caller = outer;
    _ = try ctx.callMethod(obj, "__construct", bound.list.items);
    return NativeResult.borrowed(.{ .object = obj });
}

fn raGetTarget(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const target = this.get("__target");
    return if (target == .int) NativeResult.share(target) else NativeResult.scalar(.{ .int = 0 });
}

fn raIsRepeated(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const repeated = this.get("__is_repeated");
    return if (repeated == .bool) NativeResult.share(repeated) else NativeResult.scalar(.{ .bool = false });
}

fn reConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = try classObjectCtor(ctx, this, args, "ReflectionEnum::__construct");
    const is_enum = if (ctx.vm.classes.get(class_name)) |cls| cls.is_enum else false;
    if (!is_enum) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" is not an enum", .{class_name});
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    return NativeResult.scalar(.null);
}

fn reIsBacked(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cls.backed_type != .none });
}

fn reGetBackingType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.null);
    const type_name: []const u8 = switch (cls.backed_type) {
        .none => return NativeResult.scalar(.null),
        .int_type => "int",
        .string_type => "string",
    };
    const obj = try createNamedTypeObj(ctx, type_name, false);
    return NativeResult.borrowed(.{ .object = obj });
}

fn reGetCases(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const arr = try ctx.createArray();
    for (cls.case_order.items) |case_name| {
        const case_obj = try buildEnumCase(ctx, class_name, case_name, cls.backed_type != .none);
        try arr.append(ctx.allocator, .{ .object = case_obj });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn reGetCase(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = try zpp.str(ctx, "ReflectionEnum::getCase", args, 0, "name");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.null);
    if (findConstantOwner(ctx, class_name, name, 0) == null) return throwReflectionFmt(ctx, "Case {s}::{s} does not exist", .{ class_name, name });
    if (!containsName(cls.case_order.items, name)) return throwReflectionFmt(ctx, "{s}::{s} is not a case", .{ class_name, name });
    const obj = try buildEnumCase(ctx, class_name, name, cls.backed_type != .none);
    return NativeResult.borrowed(.{ .object = obj });
}

fn reHasCase(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    for (cls.case_order.items) |case_name| {
        if (std.mem.eql(u8, case_name, args[0].string.bytes())) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn buildEnumCase(ctx: *NativeContext, class_name: []const u8, case_name: []const u8, is_backed: bool) !*PhpObject {
    const obj_class: []const u8 = if (is_backed) "ReflectionEnumBackedCase" else "ReflectionEnumUnitCase";
    const obj = try ctx.createObject(obj_class);
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(case_name) });
    try obj.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(class_name) });
    return obj;
}

fn reucConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const owner = try bindClassConstant(ctx, args);
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = this.get("name").string.bytes();
    const cls = ctx.vm.classes.get(owner);
    const is_case = if (cls) |c| containsName(c.case_order.items, name) else false;
    if (!is_case) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Constant {s}::{s} is not a case", .{ owner, name });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    if (ctx.vm.isInstanceOf(this.class_name, "ReflectionEnumBackedCase") and !enumIsBacked(ctx.vm, owner)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Enum case {s}::{s} is not a backed case", .{ owner, name });
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    return NativeResult.scalar(.null);
}

fn rzextConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const name = if (args.len > 0 and args[0] == .string) args[0].string.bytes() else "";
    const msg = try std.fmt.allocPrint(ctx.allocator, "Zend Extension \"{s}\" does not exist", .{name});
    defer ctx.allocator.free(msg);
    return throwReflection(ctx, msg);
}

fn containsName(names: []const []const u8, name: []const u8) bool {
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn reucGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn reucGetValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.null);
    const case_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.null);
    return NativeResult.share(ctx.vm.enumCase(cls.constants.get(case_name) orelse .null));
}

fn rebcGetBackingValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.null);
    const case_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.null);
    const case_obj_v = cls.constants.get(case_name) orelse return NativeResult.scalar(.null);
    if (case_obj_v != .object) return NativeResult.scalar(.null);
    return NativeResult.share(case_obj_v.object.get("value"));
}

const Generator = @import("../runtime/value.zig").Generator;

fn rgConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args[0] != .generator) return zpp.typeError(ctx, "ReflectionGenerator::__construct", 0, "generator", "Generator", args[0]);
    // the reflector keeps the generator alive, as php's does
    try obj.set(ctx.allocator, "__gen", args[0]);
    return NativeResult.scalar(.null);
}

fn getGenPtr(obj: *PhpObject) ?*Generator {
    const v = obj.get("__gen");
    return if (v == .generator) v.generator else null;
}

// REFLECTION_CHECK_VALID_GENERATOR: a finished generator has no frame left
fn openGenerator(ctx: *NativeContext) RuntimeError!*Generator {
    const obj = getThis(ctx) orelse return throwReflection(ctx, "Cannot fetch information from a closed Generator");
    const gen = getGenPtr(obj) orelse return throwReflection(ctx, "Cannot fetch information from a closed Generator");
    if (gen.state == .completed) return throwReflection(ctx, "Cannot fetch information from a closed Generator");
    return gen;
}

fn generatorLine(ctx: *NativeContext, gen: *const Generator) i64 {
    // one not yet started is at its declaration
    if (gen.state == .created) return @intCast(gen.func.start_line);
    const ip = if (gen.ip > 0) gen.ip - 1 else 0;
    if (ctx.vm.sourceLocation(&gen.func.chunk, ip)) |loc| return @intCast(loc.line);
    return @intCast(gen.func.start_line);
}

fn rgGetExecutingLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const gen = try openGenerator(ctx);
    return NativeResult.scalar(.{ .int = generatorLine(ctx, gen) });
}

fn rgGetExecutingFile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const gen = try openGenerator(ctx);
    return try NativeResult.copyString(ctx.allocator, if (gen.func.file_path.len > 0) gen.func.file_path else ctx.vm.file_path);
}

fn rgIsClosed(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const gen = getGenPtr(obj) orelse return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = gen.state == .completed });
}

// a generator's function as php's reflection factories give it: the
// closure, the method, or the function
fn rgGetFunction(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = getGenPtr(obj) orelse return NativeResult.scalar(.null);
    const name = gen.func.name;
    if (gen.closure) |owner| {
        const closure: Value = .{ .object = owner };
        const rf = try ctx.createObject("ReflectionFunction");
        _ = try ctx.callMethod(rf, "__construct", &.{closure});
        return NativeResult.borrowed(.{ .object = rf });
    }
    if (std.mem.indexOf(u8, name, "::") != null) {
        const rm = try ctx.createObject("ReflectionMethod");
        _ = try initMethodReflection(ctx, rm, &.{.{ .string = Value.String.borrowed(try ctx.vm.internName(name)) }}, false);
        return NativeResult.borrowed(.{ .object = rm });
    }
    const rf = try ctx.createObject("ReflectionFunction");
    _ = try ctx.callMethod(rf, "__construct", &.{.{ .string = Value.String.borrowed(try ctx.vm.internName(name)) }});
    return NativeResult.borrowed(.{ .object = rf });
}

fn rgGetThis(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const gen = try openGenerator(ctx);
    if (gen.vars.get("$this")) |this_v| if (this_v == .object) return NativeResult.share(this_v);
    return NativeResult.scalar(.null);
}

fn innermostGenerator(gen: *Generator) *Generator {
    var current = gen;
    while (current.delegate) |del| switch (del) {
        .gen => |inner| current = inner,
        else => break,
    };
    return current;
}

fn rgGetExecutingGenerator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const gen = try openGenerator(ctx);
    return NativeResult.borrowed(.{ .generator = innermostGenerator(gen) });
}

// the backtrace of the generator's yield from chain, innermost first: each
// frame names its function and, but for the outermost, the line its
// delegator waits at
fn rgGetTrace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const options: i64 = if (args.len > 0) (try zpp.long(ctx, "ReflectionGenerator::getTrace", args, 0, "options", false)) orelse 1 else 1;
    const gen = try openGenerator(ctx);
    var chain: std.ArrayListUnmanaged(*Generator) = .empty;
    defer chain.deinit(ctx.allocator);
    var current: ?*Generator = gen;
    while (current) |g| {
        try chain.append(ctx.allocator, g);
        current = if (g.delegate) |del| switch (del) {
            .gen => |inner| inner,
            else => null,
        } else null;
    }
    std.mem.reverse(*Generator, chain.items);
    const arr = try ctx.createArray();
    for (chain.items, 0..) |g, i| {
        const frame = try ctx.createArray();
        if (i + 1 < chain.items.len) {
            const caller = chain.items[i + 1];
            try frame.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("file") }, if (caller.func.file_path.len > 0) caller.func.file_path else ctx.vm.file_path);
            try frame.set(ctx.allocator, .{ .string = Value.String.borrowed("line") }, .{ .int = generatorLine(ctx, caller) });
        }
        const full = g.func.name;
        const display = if (g.func.display_name.len > 0) g.func.display_name else full;
        if (std.mem.indexOf(u8, full, "::")) |sep| {
            try frame.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("function") }, full[sep + 2 ..]);
            try frame.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("class") }, full[0..sep]);
            const this_v = g.vars.get("$this");
            if (this_v != null and this_v.? == .object) {
                if (options & 1 != 0) try frame.set(ctx.allocator, .{ .string = Value.String.borrowed("object") }, this_v.?);
                try frame.set(ctx.allocator, .{ .string = Value.String.borrowed("type") }, .{ .string = Value.String.borrowed("->") });
            } else {
                try frame.set(ctx.allocator, .{ .string = Value.String.borrowed("type") }, .{ .string = Value.String.borrowed("::") });
            }
        } else {
            try frame.setCopiedString(ctx.allocator, .{ .string = Value.String.borrowed("function") }, display);
        }
        if (options & 2 == 0) {
            const call_args = try ctx.createArray();
            for (g.func.params) |param| {
                const v = g.vars.get(param) orelse continue;
                try call_args.append(ctx.allocator, v);
            }
            try frame.set(ctx.allocator, .{ .string = Value.String.borrowed("args") }, .{ .array = call_args });
        }
        try arr.append(ctx.allocator, .{ .array = frame });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

const Fiber = @import("../runtime/value.zig").Fiber;

fn rfibConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args[0] != .fiber) return zpp.typeError(ctx, "ReflectionFiber::__construct", 0, "fiber", "Fiber", args[0]);
    // the reflector keeps the fiber alive, as php's does
    try obj.set(ctx.allocator, "__fib", args[0]);
    return NativeResult.scalar(.null);
}

fn getFibPtr(obj: *PhpObject) ?*Fiber {
    const v = obj.get("__fib");
    return if (v == .fiber) v.fiber else null;
}

// REFLECTION_CHECK_VALID_FIBER
fn startedFiber(ctx: *NativeContext) RuntimeError!*Fiber {
    const obj = getThis(ctx) orelse return fiberGone(ctx);
    const fib = getFibPtr(obj) orelse return fiberGone(ctx);
    if (fib.state == .created or fib.state == .terminated) return fiberGone(ctx);
    return fib;
}

fn fiberGone(ctx: *NativeContext) RuntimeError {
    _ = try ctx.vm.throwBuiltinException("Error", "Cannot fetch information from a fiber that has not been started or is terminated");
    return error.RuntimeError;
}

// the user frame the fiber runs: the current one while it runs, the one
// that suspended it otherwise
const FiberPosition = struct { file: []const u8, line: i64 };

fn fiberPosition(ctx: *NativeContext, fib: *Fiber) ?FiberPosition {
    if (ctx.vm.current_fiber == fib) {
        const frame = ctx.vm.currentFrame();
        const ip = if (frame.ip > 0) frame.ip - 1 else 0;
        const loc = ctx.vm.sourceLocation(frame.chunk, ip) orelse return null;
        return .{ .file = ctx.vm.frameFile(ctx.vm.frame_count - 1), .line = @intCast(loc.line) };
    }
    if (fib.saved_frames.items.len == 0) return null;
    return savedFramePosition(ctx, &fib.saved_frames.items[fib.saved_frames.items.len - 1]);
}

fn savedFramePosition(ctx: *NativeContext, frame: *const Fiber.SavedFrame) ?FiberPosition {
    const ip = if (frame.ip > 0) frame.ip - 1 else 0;
    const loc = ctx.vm.sourceLocation(frame.chunk, ip) orelse return null;
    const file = if (frame.func) |f| (if (f.file_path.len > 0) f.file_path else ctx.vm.file_path) else ctx.vm.file_path;
    return .{ .file = file, .line = @intCast(loc.line) };
}

fn rfibGetExecutingLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const fib = try startedFiber(ctx);
    const pos = fiberPosition(ctx, fib) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = pos.line });
}

fn rfibGetExecutingFile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const fib = try startedFiber(ctx);
    const pos = fiberPosition(ctx, fib) orelse return NativeResult.scalar(.null);
    return try NativeResult.copyString(ctx.allocator, pos.file);
}

fn rfibGetCallable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fib = getFibPtr(obj) orelse return NativeResult.scalar(.null);
    if (fib.state == .terminated) {
        _ = try ctx.vm.throwBuiltinException("Error", "Cannot fetch the callable from a fiber that has terminated");
        return error.RuntimeError;
    }
    return NativeResult.share(fib.callable);
}

fn rfibGetFiber(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fib = getFibPtr(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .fiber = fib });
}

fn traceSet(ctx: *NativeContext, entry: *PhpArray, key: []const u8, v: Value) RuntimeError!void {
    try entry.set(ctx.allocator, .{ .string = Value.String.borrowed(key) }, v);
}

// a suspended fiber's backtrace: the Fiber::suspend() call, then the
// fiber's frames, innermost first
fn rfibGetTrace(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const options: i64 = if (args.len > 0) (try zpp.long(ctx, "ReflectionFiber::getTrace", args, 0, "options", false)) orelse 1 else 1;
    const fib = try startedFiber(ctx);
    if (ctx.vm.current_fiber == fib) {
        // within the fiber the trace is debug_backtrace's
        const all = try ctx.vm.callByName("debug_backtrace", &.{.{ .int = if (options & 1 != 0) 0 else 1 }});
        return NativeResult.share(all);
    }
    const arr = try ctx.createArray();
    const frames = fib.saved_frames.items;
    if (frames.len > 0) {
        const entry = try ctx.createArray();
        if (savedFramePosition(ctx, &frames[frames.len - 1])) |pos| {
            try traceSet(ctx, entry, "file", .{ .string = Value.String.borrowed(pos.file) });
            try traceSet(ctx, entry, "line", .{ .int = pos.line });
        }
        try traceSet(ctx, entry, "function", .{ .string = Value.String.borrowed("suspend") });
        try traceSet(ctx, entry, "class", .{ .string = Value.String.borrowed("Fiber") });
        try traceSet(ctx, entry, "type", .{ .string = Value.String.borrowed("::") });
        if (options & 2 == 0) try traceSet(ctx, entry, "args", .{ .array = try ctx.createArray() });
        try arr.append(ctx.allocator, .{ .array = entry });
    }
    var k = frames.len;
    while (k > 0) {
        k -= 1;
        const frame = &frames[k];
        const func = frame.func orelse continue;
        const entry = try ctx.createArray();
        if (k > 0) if (savedFramePosition(ctx, &frames[k - 1])) |pos| {
            try traceSet(ctx, entry, "file", .{ .string = Value.String.borrowed(pos.file) });
            try traceSet(ctx, entry, "line", .{ .int = pos.line });
        };
        if (std.mem.indexOf(u8, func.name, "::")) |sep| {
            try traceSet(ctx, entry, "function", .{ .string = Value.String.borrowed(try ctx.vm.phpMethodName(func.name[sep + 2 ..])) });
            try traceSet(ctx, entry, "class", .{ .string = Value.String.borrowed(func.name[0..sep]) });
            const this_v = frame.vars.get("$this");
            if (this_v != null and this_v.? == .object and options & 1 != 0) try traceSet(ctx, entry, "object", this_v.?);
            try traceSet(ctx, entry, "type", .{ .string = Value.String.borrowed(if (func.is_static) "::" else "->") });
        } else {
            try traceSet(ctx, entry, "function", .{ .string = Value.String.borrowed(try ctx.vm.funcDisplayName(func)) });
        }
        if (options & 2 == 0) try traceSet(ctx, entry, "args", .{ .array = try ctx.createArray() });
        try arr.append(ctx.allocator, .{ .array = entry });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn hasDeprecatedAttribute(attrs: []const AttributeDef) bool {
    for (attrs) |attr| {
        const name = std.mem.trimStart(u8, attr.name, "\\");
        if (std.ascii.eqlIgnoreCase(name, "Deprecated")) return true;
    }
    return false;
}

// the #[Attribute(flags)] argument list of a built-in attribute class, owned
// by the class def like any parsed attribute's
fn attributeTargets(a: Allocator, flags: i64) ![]Value {
    return a.dupe(Value, &[_]Value{.{ .int = flags }});
}

// Deprecated($message, $since) and NoDiscard($message): the arguments land on
// the readonly properties of the same names
fn deprecatedConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    try refuseReconstruction(ctx, this, "Deprecated");
    try setNullableStringParam(ctx, this, args, 0, "Deprecated", "message");
    try setNullableStringParam(ctx, this, args, 1, "Deprecated", "since");
    try this.set(ctx.allocator, "__constructed", .{ .bool = true });
    return NativeResult.scalar(.null);
}

fn noDiscardConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    try refuseReconstruction(ctx, this, "NoDiscard");
    try setNullableStringParam(ctx, this, args, 0, "NoDiscard", "message");
    try this.set(ctx.allocator, "__constructed", .{ .bool = true });
    return NativeResult.scalar(.null);
}

// the properties are readonly: a second __construct() call writes them again
fn refuseReconstruction(ctx: *NativeContext, this: *PhpObject, comptime class: []const u8) RuntimeError!void {
    if (this.get("__constructed") != .bool) return;
    try ctx.vm.setPendingException("Error", "Cannot modify readonly property " ++ class ++ "::$message");
    return error.RuntimeError;
}

// a `?string $name = null` constructor parameter stored as the property of
// that name, with php's checks: scalars become strings unless the caller is
// strict, anything else is a TypeError
fn setNullableStringParam(ctx: *NativeContext, this: *PhpObject, args: []const Value, index: usize, comptime class: []const u8, comptime name: []const u8) RuntimeError!void {
    if (index >= args.len) return;
    const arg = args[index];
    const value: Value = switch (arg) {
        .null, .string => arg,
        .int, .float, .bool => if (ctx.vm.topFrameStrict()) .undef else {
            var buf = std.ArrayListUnmanaged(u8).empty;
            defer buf.deinit(ctx.allocator);
            try arg.format(&buf, ctx.allocator);
            return this.setCopiedString(ctx.allocator, name, buf.items);
        },
        else => .undef,
    };
    if (value == .undef) {
        const msg = try std.fmt.allocPrint(ctx.allocator, class ++ "::__construct(): Argument #{d} ($" ++ name ++ ") must be of type ?string, {s} given", .{ index + 1, arg.valueName() });
        defer ctx.allocator.free(msg);
        try ctx.vm.setPendingException("TypeError", msg);
        return error.RuntimeError;
    }
    try this.set(ctx.allocator, name, value);
}

fn rfIsDeprecated(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func_name = if (functionKey(this) == .string) functionKey(this).string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.native_fns.get(func_name)) |native| return NativeResult.scalar(.{ .bool = native.deprecated != null });
    const attrs = ctx.vm.function_attributes.get(compiledFunctionName(ctx.vm, func_name)) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = hasDeprecatedAttribute(attrs) });
}

fn rmIsDeprecated(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .bool = false });
    const declaring = if (this.get("__declaring_class") == .string) this.get("__declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.is_internal) {
        var buf: [256]u8 = undefined;
        const key = methodKey(this, &buf, declaring, method_name);
        return NativeResult.scalar(.{ .bool = deprecations.functions.has(key) });
    }
    const attrs = cls.method_attributes.get(method_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = hasDeprecatedAttribute(attrs) });
}

fn rccIsDeprecated(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.is_internal) {
        var buf: [256]u8 = undefined;
        const key = class_names.memberKey(&buf, class_name, const_name);
        return NativeResult.scalar(.{ .bool = deprecations.class_constants.has(key) });
    }
    const attrs = cls.constant_attributes.get(const_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = hasDeprecatedAttribute(attrs) });
}

fn rconstIsDeprecated(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (deprecations.constants.has(name)) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = ctx.vm.deprecated_globals.contains(name) });
}

fn rconstGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    try checkAttributeFilter(ctx, args, "ReflectionConstant");
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const name = this.get("name");
    if (name != .string) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const key = ctx.vm.constant_attributes.get(name.string.bytes()) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const attrs = ctx.vm.function_attributes.get(key) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 64, flags, "");
}

fn rconstConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionConstant::__construct() expects a constant name");
    const name = std.mem.trimStart(u8, args[0].string.bytes(), "\\");
    if (!ctx.vm.php_constants.contains(name)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Constant \"{s}\" does not exist", .{name}) catch return throwReflection(ctx, "Constant does not exist");
        defer ctx.allocator.free(msg);
        return throwReflection(ctx, msg);
    }
    const owned = try Value.String.create(ctx.allocator, name);
    defer owned.release();
    try this.set(ctx.allocator, "name", .{ .string = owned });
    return NativeResult.scalar(.null);
}

fn rconstGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rconstGetValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.null);
    return NativeResult.share(ctx.vm.php_constants.get(name_v.string.bytes()) orelse .null);
}

fn rconstGetShortName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.null);
    const name = name_v.string.bytes();
    const pos = std.mem.lastIndexOfScalar(u8, name, '\\') orelse return NativeResult.shareString(name_v.string);
    return try NativeResult.copyString(ctx.allocator, name[pos + 1 ..]);
}

fn rconstGetNamespaceName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.literal("");
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.literal("");
    const name = name_v.string.bytes();
    const pos = std.mem.lastIndexOfScalar(u8, name, '\\') orelse return NativeResult.literal("");
    return try NativeResult.copyString(ctx.allocator, name[0..pos]);
}

fn rconstToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.literal("");
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.literal("");
    const name = name_v.string.bytes();
    const value = ctx.vm.php_constants.get(name) orelse Value.null;
    // the runtime's own constants are php's persistent ones
    const persistent = !ctx.vm.user_constants.contains(name);
    const deprecated = deprecations.constants.has(name) or ctx.vm.deprecated_globals.contains(name);
    return @import("reflection_string.zig").constantString(ctx, name, value, persistent, deprecated);
}

// resetAsLazyGhost / resetAsLazyProxy: an existing instance drops every
// property value it holds and becomes lazy again around the new initializer
fn rcResetAsLazy(ctx: *NativeContext, args: []const Value, proxy: bool) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .object) return NativeResult.scalar(.null);
    const obj = args[0].object;
    const method: []const u8 = if (proxy) "resetAsLazyProxy" else "resetAsLazyGhost";
    if (getThis(ctx)) |this| if (this.get("name") == .string) {
        const class_name = this.get("name").string.bytes();
        if (!ctx.vm.isInstanceOf(obj.class_name, class_name)) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "ReflectionClass::{s}(): Argument #1 ($object) must be of type {s}, {s} given", .{ method, ctx.vm.declaredClassName(class_name), obj.class_name });
            defer ctx.allocator.free(msg);
            _ = try ctx.vm.throwBuiltinException("TypeError", msg);
            return error.RuntimeError;
        }
        try lazyPreconditions(ctx, class_name, if (args.len > 2) args[2] else null, obj, method);
    };
    // the object is destructed first, unless asked not to or done already
    const skip_destructor = args.len > 2 and args[2] == .int and (args[2].int & 16) != 0;
    if (!skip_destructor and !obj.destructor_called and obj.lazy == null and ctx.vm.hasMethod(obj.class_name, "__destruct")) {
        obj.destructor_called = true;
        obj.refcount +%= 1;
        defer obj.refcount -%= 1;
        _ = try ctx.vm.callMethod(obj, "__destruct", &.{});
    }
    obj.destructor_called = false;
    if (obj.lazy) |state| {
        if (state.initializer != .null) ctx.vm.releaseValue(state.initializer);
        ctx.allocator.free(state.pending);
        ctx.allocator.destroy(state);
        obj.lazy = null;
    }
    if (obj.slots) |slots| {
        for (slots) |v| ctx.vm.releaseValue(v);
        ctx.allocator.free(slots);
        obj.slots = null;
    }
    for (obj.properties.values()) |v| ctx.vm.releaseValue(v);
    obj.clearProperties(ctx.allocator);
    try ctx.vm.initObjectProperties(obj, obj.class_name);
    VM.retainValue(args[1]);
    const state = try ctx.allocator.create(PhpObject.LazyState);
    const count = if (obj.slots) |slots| slots.len else 0;
    state.* = .{ .initializer = args[1], .proxy = proxy, .pending = try ctx.allocator.alloc(bool, count), .skip_serialize = args.len > 2 and args[2] == .int and (args[2].int & 8) != 0 };
    @memset(state.pending, true);
    obj.lazy = state;
    if (count == 0) {
        ctx.vm.releaseValue(state.initializer);
        state.initializer = .null;
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn rcResetAsLazyGhost(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return rcResetAsLazy(ctx, args, false);
}

fn rcResetAsLazyProxy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return rcResetAsLazy(ctx, args, true);
}

fn rcGetLazyInitializer(_: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const state = args[0].object.lazy orelse return NativeResult.scalar(.null);
    if (state.initializer == .null) return NativeResult.scalar(.null);
    return NativeResult.share(state.initializer);
}
