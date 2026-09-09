const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;
const AttributeDef = vm_mod.AttributeDef;
const ObjFunction = @import("../pipeline/bytecode.zig").ObjFunction;
const NativeResult = @import("../runtime/native_result.zig").NativeResult;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

fn retainReturned(value: Value) Value {
    if (value == .string) value.string.retain();
    return value;
}

pub fn register(vm: *VM, a: Allocator) !void {
    // Unit enum cases are request-lifetime objects, just like RoundingMode.
    var hook_type = ClassDef{ .name = "PropertyHookType", .is_enum = true, .is_final = true };
    for ([_][]const u8{ "Get", "Set" }) |name| {
        const obj = try a.create(PhpObject);
        vm.next_object_id += 1;
        obj.* = .{ .class_name = "PropertyHookType", .id = vm.next_object_id };
        try vm.objects.append(a, obj);
        try obj.set(a, "name", .{ .string = Value.String.borrowed(name) });
        VM.objRetain(obj);
        try hook_type.static_props.put(a, name, .{ .object = obj });
        try hook_type.constant_names.put(a, name, {});
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
    try vm.interfaces.put(a, "Reflector", reflector_iface);

    // ReflectionType abstract base class. ReflectionNamedType / Union / Intersection
    // all extend it. registering as a concrete class is fine since user code only
    // checks instanceof / get_parent_class
    var rt_def = ClassDef{ .name = "ReflectionType" };
    rt_def.is_abstract = true;
    try rt_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rt_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionType", rt_def);

    var attr_def = ClassDef{ .name = "Attribute" };
    try attr_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try attr_def.static_props.put(a, "TARGET_CLASS", .{ .int = 1 });
    try attr_def.static_props.put(a, "TARGET_FUNCTION", .{ .int = 2 });
    try attr_def.static_props.put(a, "TARGET_METHOD", .{ .int = 4 });
    try attr_def.static_props.put(a, "TARGET_PROPERTY", .{ .int = 8 });
    try attr_def.static_props.put(a, "TARGET_CLASS_CONSTANT", .{ .int = 16 });
    try attr_def.static_props.put(a, "TARGET_PARAMETER", .{ .int = 32 });
    try attr_def.static_props.put(a, "TARGET_ALL", .{ .int = 127 });
    try attr_def.static_props.put(a, "IS_REPEATABLE", .{ .int = 128 });
    try vm.classes.put(a, "Attribute", attr_def);
    try vm.native_fns.put(a, "Attribute::__construct", attributeConstruct);

    // PHP 8.3 #[Override] marker. enforcement happens elsewhere - here we
    // register the class so attribute reflection and class_exists pick it up
    var override_def = ClassDef{ .name = "Override" };
    try override_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try override_def.attributes.append(a, .{ .name = "Attribute", .args = &.{} });
    try vm.classes.put(a, "Override", override_def);

    // PHP 8.2 #[SensitiveParameter] - marks parameters whose values should be
    // redacted from stack traces. Stub the class for attribute usage
    var sp_def = ClassDef{ .name = "SensitiveParameter" };
    try sp_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 0 });
    try sp_def.attributes.append(a, .{ .name = "Attribute", .args = &.{} });
    try vm.classes.put(a, "SensitiveParameter", sp_def);

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
    try rc_def.static_props.put(a, "SKIP_INITIALIZATION_ON_SERIALIZE", .{ .int = 8 });
    try rc_def.constant_names.put(a, "SKIP_INITIALIZATION_ON_SERIALIZE", {});
    try rc_def.methods.put(a, "newLazyGhost", .{ .name = "newLazyGhost", .arity = 1 });
    try rc_def.methods.put(a, "newLazyProxy", .{ .name = "newLazyProxy", .arity = 1 });
    try rc_def.methods.put(a, "initializeLazyObject", .{ .name = "initializeLazyObject", .arity = 1 });
    try rc_def.methods.put(a, "isUninitializedLazyObject", .{ .name = "isUninitializedLazyObject", .arity = 1 });
    try rc_def.methods.put(a, "markLazyObjectAsInitialized", .{ .name = "markLazyObjectAsInitialized", .arity = 1 });
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

    // ReflectionObject extends ReflectionClass. behavior is identical to
    // ReflectionClass(get_class($obj)) when constructed with an instance,
    // so register an empty subclass and let method dispatch fall through
    var ro_def = ClassDef{ .name = "ReflectionObject", .parent = "ReflectionClass" };
    try ro_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try vm.classes.put(a, "ReflectionObject", ro_def);

    const rfa_def = ClassDef{ .name = "ReflectionFunctionAbstract", .is_abstract = true };
    try vm.classes.put(a, "ReflectionFunctionAbstract", rfa_def);

    var rm_def = ClassDef{ .name = "ReflectionMethod", .parent = "ReflectionFunctionAbstract" };
    try rm_def.static_props.put(a, "IS_STATIC", .{ .int = 16 });
    try rm_def.static_props.put(a, "IS_PUBLIC", .{ .int = 1 });
    try rm_def.static_props.put(a, "IS_PROTECTED", .{ .int = 2 });
    try rm_def.static_props.put(a, "IS_PRIVATE", .{ .int = 4 });
    try rm_def.static_props.put(a, "IS_ABSTRACT", .{ .int = 64 });
    try rm_def.static_props.put(a, "IS_FINAL", .{ .int = 32 });
    try rm_def.constant_names.put(a, "IS_STATIC", {});
    try rm_def.constant_names.put(a, "IS_PUBLIC", {});
    try rm_def.constant_names.put(a, "IS_PROTECTED", {});
    try rm_def.constant_names.put(a, "IS_PRIVATE", {});
    try rm_def.constant_names.put(a, "IS_ABSTRACT", {});
    try rm_def.constant_names.put(a, "IS_FINAL", {});
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
    try vm.classes.put(a, "ReflectionMethod", rm_def);

    try vm.native_fns.put(a, "ReflectionMethod::__construct", rmConstruct);
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
    try vm.native_fns.put(a, "ReflectionMethod::hasTentativeReturnType", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionMethod::getTentativeReturnType", reflectionNoop);
    try vm.native_fns.put(a, "ReflectionMethod::invokeArgs", rmInvokeArgs);
    try vm.native_fns.put(a, "ReflectionMethod::isAbstract", rmIsAbstract);
    try vm.native_fns.put(a, "ReflectionMethod::isFinal", rmIsFinal);
    try vm.native_fns.put(a, "ReflectionMethod::isVariadic", rmIsVariadic);
    try vm.native_fns.put(a, "ReflectionMethod::isGenerator", rmIsGenerator);
    try vm.native_fns.put(a, "ReflectionMethod::returnsReference", reflectionFalse);
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
    try vm.native_fns.put(a, "ReflectionMethod::isDeprecated", reflectionFalse);

    var rp_def = ClassDef{ .name = "ReflectionParameter" };
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
    try vm.native_fns.put(a, "ReflectionParameter::isDefaultValueConstant", rpIsDefaultValueConstant);
    try vm.native_fns.put(a, "ReflectionParameter::getDefaultValueConstantName", rpGetDefaultValueConstantName);

    var rnt_def = ClassDef{ .name = "ReflectionNamedType", .parent = "ReflectionType" };
    try rnt_def.properties.append(a, .{ .name = "type_name", .default = .{ .string = Value.String.borrowed("") } });
    try rnt_def.properties.append(a, .{ .name = "nullable", .default = .{ .bool = false } });
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
    try rut_def.properties.append(a, .{ .name = "type_str", .default = .{ .string = Value.String.borrowed("") } });
    try rut_def.properties.append(a, .{ .name = "nullable", .default = .{ .bool = false } });
    try rut_def.methods.put(a, "getTypes", .{ .name = "getTypes", .arity = 0 });
    try rut_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rut_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionUnionType", rut_def);
    try vm.native_fns.put(a, "ReflectionUnionType::getTypes", rutGetTypes);
    try vm.native_fns.put(a, "ReflectionUnionType::allowsNull", rutAllowsNull);
    try vm.native_fns.put(a, "ReflectionUnionType::__toString", rutToString);

    var rit_def = ClassDef{ .name = "ReflectionIntersectionType", .parent = "ReflectionType" };
    try rit_def.properties.append(a, .{ .name = "type_str", .default = .{ .string = Value.String.borrowed("") } });
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

    var reuc_def = ClassDef{ .name = "ReflectionEnumUnitCase" };
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
    try vm.native_fns.put(a, "ReflectionFunction::returnsReference", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureScopeClass", rfGetClosureScopeClass);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureThis", rfGetClosureThis);
    try vm.native_fns.put(a, "ReflectionFunction::isStatic", rfIsStatic);
    try vm.native_fns.put(a, "ReflectionFunction::hasReturnType", rfHasReturnType);
    try vm.native_fns.put(a, "ReflectionFunction::getAttributes", rfGetAttributes);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureUsedVariables", rfGetClosureUsedVariables);
    try vm.native_fns.put(a, "ReflectionFunction::getStaticVariables", rfGetClosureUsedVariables);
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
    try vm.native_fns.put(a, "ReflectionFunction::getExtension", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionFunction::getExtensionName", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionFunction::isDeprecated", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionFunction::isDisabled", reflectionFalse);

    var rprop_def = ClassDef{ .name = "ReflectionProperty" };
    try rprop_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    try rprop_def.properties.append(a, .{ .name = "class", .default = .{ .string = Value.String.borrowed("") } });
    try rprop_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try rprop_def.methods.put(a, "setAccessible", .{ .name = "setAccessible", .arity = 1 });
    try rprop_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 1 });
    try rprop_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rprop_def.methods.put(a, "getType", .{ .name = "getType", .arity = 0 });
    try rprop_def.methods.put(a, "isPublic", .{ .name = "isPublic", .arity = 0 });
    try rprop_def.methods.put(a, "isProtected", .{ .name = "isProtected", .arity = 0 });
    try rprop_def.methods.put(a, "isPrivate", .{ .name = "isPrivate", .arity = 0 });
    try rprop_def.methods.put(a, "getDefaultValue", .{ .name = "getDefaultValue", .arity = 0 });
    try rprop_def.methods.put(a, "hasDefaultValue", .{ .name = "hasDefaultValue", .arity = 0 });
    try rprop_def.methods.put(a, "isInitialized", .{ .name = "isInitialized", .arity = 1 });
    try rprop_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rprop_def.methods.put(a, "isDefault", .{ .name = "isDefault", .arity = 0 });
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
    try rprop_def.static_props.put(a, "IS_STATIC", .{ .int = 16 });
    try rprop_def.static_props.put(a, "IS_READONLY", .{ .int = 128 });
    try rprop_def.static_props.put(a, "IS_PUBLIC", .{ .int = 1 });
    try rprop_def.static_props.put(a, "IS_PROTECTED", .{ .int = 2 });
    try rprop_def.static_props.put(a, "IS_PRIVATE", .{ .int = 4 });
    try rprop_def.static_props.put(a, "IS_ABSTRACT", .{ .int = 64 });
    try rprop_def.static_props.put(a, "IS_PROTECTED_SET", .{ .int = 2048 });
    try rprop_def.static_props.put(a, "IS_PRIVATE_SET", .{ .int = 4096 });
    try rprop_def.static_props.put(a, "IS_VIRTUAL", .{ .int = 512 });
    try rprop_def.static_props.put(a, "IS_FINAL", .{ .int = 32 });
    try rprop_def.constant_names.put(a, "IS_STATIC", {});
    try rprop_def.constant_names.put(a, "IS_READONLY", {});
    try rprop_def.constant_names.put(a, "IS_PUBLIC", {});
    try rprop_def.constant_names.put(a, "IS_PROTECTED", {});
    try rprop_def.constant_names.put(a, "IS_PRIVATE", {});
    try rprop_def.constant_names.put(a, "IS_ABSTRACT", {});
    try rprop_def.constant_names.put(a, "IS_PROTECTED_SET", {});
    try rprop_def.constant_names.put(a, "IS_PRIVATE_SET", {});
    try rprop_def.constant_names.put(a, "IS_VIRTUAL", {});
    try rprop_def.constant_names.put(a, "IS_FINAL", {});
    try vm.classes.put(a, "ReflectionProperty", rprop_def);

    try vm.native_fns.put(a, "ReflectionProperty::__construct", rpConstruct);
    try vm.native_fns.put(a, "ReflectionProperty::setAccessible", reflectionNoop);
    try vm.native_fns.put(a, "ReflectionProperty::getValue", rpGetValue);
    try vm.native_fns.put(a, "ReflectionProperty::getRawValue", rpGetValue);
    try vm.native_fns.put(a, "ReflectionProperty::setValue", rpSetValue);
    try vm.native_fns.put(a, "ReflectionProperty::setRawValue", rpSetValue);
    try vm.native_fns.put(a, "ReflectionProperty::setRawValueWithoutLazyInitialization", rpSetWithoutLazy);
    try vm.native_fns.put(a, "ReflectionProperty::getName", rpropGetName);
    try vm.native_fns.put(a, "ReflectionProperty::getType", rpropGetType);
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
    try ra_def.static_props.put(a, "IS_INSTANCEOF", .{ .int = 2 });
    try ra_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try ra_def.methods.put(a, "getArguments", .{ .name = "getArguments", .arity = 0 });
    try ra_def.methods.put(a, "newInstance", .{ .name = "newInstance", .arity = 0 });
    try ra_def.methods.put(a, "getTarget", .{ .name = "getTarget", .arity = 0 });
    try ra_def.methods.put(a, "isRepeated", .{ .name = "isRepeated", .arity = 0 });
    try vm.classes.put(a, "ReflectionAttribute", ra_def);

    try vm.native_fns.put(a, "ReflectionAttribute::getName", raGetName);
    try vm.native_fns.put(a, "ReflectionAttribute::getArguments", raGetArguments);
    try vm.native_fns.put(a, "ReflectionAttribute::newInstance", raNewInstance);
    try vm.native_fns.put(a, "ReflectionAttribute::getTarget", raGetTarget);
    try vm.native_fns.put(a, "ReflectionAttribute::isRepeated", raIsRepeated);

    var rcc_def = ClassDef{ .name = "ReflectionClassConstant" };
    inline for (.{ .{ "IS_PUBLIC", 1 }, .{ "IS_PROTECTED", 2 }, .{ "IS_PRIVATE", 4 }, .{ "IS_FINAL", 32 } }) |constant| {
        try rcc_def.static_props.put(a, constant[0], .{ .int = constant[1] });
        try rcc_def.constant_names.put(a, constant[0], {});
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
    try rcc_def.methods.put(a, "getType", .{ .name = "getType", .arity = 0 });
    try rcc_def.methods.put(a, "hasType", .{ .name = "hasType", .arity = 0 });
    try rcc_def.methods.put(a, "getModifiers", .{ .name = "getModifiers", .arity = 0 });
    try rcc_def.methods.put(a, "getDocComment", .{ .name = "getDocComment", .arity = 0 });
    try vm.classes.put(a, "ReflectionClassConstant", rcc_def);
    try vm.native_fns.put(a, "ReflectionClassConstant::getDocComment", rccGetDocComment);

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

    // Closure class (static methods only - instance methods handled in VM dispatch)
    var closure_def = ClassDef{ .name = "Closure" };
    try closure_def.methods.put(a, "bind", .{ .name = "bind", .arity = 2, .is_static = true });
    try closure_def.methods.put(a, "fromCallable", .{ .name = "fromCallable", .arity = 1, .is_static = true });
    try vm.classes.put(a, "Closure", closure_def);

    try vm.native_fns.put(a, "Closure::bind", closureBind);
    try vm.native_fns.put(a, "Closure::fromCallable", closureFromCallable);

    var rext_def = ClassDef{ .name = "ReflectionExtension" };
    try rext_def.properties.append(a, .{ .name = "name", .default = .{ .string = Value.String.borrowed("") } });
    for ([_][]const u8{
        "__construct",   "getName",     "getVersion",    "getFunctions",    "getConstants",
        "getINIEntries", "getClasses",  "getClassNames", "getDependencies", "info",
        "isPersistent",  "isTemporary", "__toString",
    }) |method| try rext_def.methods.put(a, method, .{ .name = method, .arity = if (std.mem.eql(u8, method, "__construct")) 1 else 0 });
    try vm.classes.put(a, "ReflectionExtension", rext_def);
    try vm.native_fns.put(a, "ReflectionExtension::__construct", rextConstruct);
    try vm.native_fns.put(a, "ReflectionExtension::getName", rextGetName);
    try vm.native_fns.put(a, "ReflectionExtension::getVersion", rextGetVersion);
    try vm.native_fns.put(a, "ReflectionExtension::getFunctions", reflectionEmptyArray);
    try vm.native_fns.put(a, "ReflectionExtension::getConstants", reflectionEmptyArray);
    try vm.native_fns.put(a, "ReflectionExtension::getINIEntries", reflectionEmptyArray);
    try vm.native_fns.put(a, "ReflectionExtension::getClasses", reflectionEmptyArray);
    try vm.native_fns.put(a, "ReflectionExtension::getClassNames", reflectionEmptyArray);
    try vm.native_fns.put(a, "ReflectionExtension::getDependencies", reflectionEmptyArray);
    try vm.native_fns.put(a, "ReflectionExtension::info", rextInfo);
    try vm.native_fns.put(a, "ReflectionExtension::isPersistent", reflectionTrue);
    try vm.native_fns.put(a, "ReflectionExtension::isTemporary", reflectionFalse);
    try vm.native_fns.put(a, "ReflectionExtension::__toString", rextToString);

    // virtual ClassDefs for builtin tagged-value types so ReflectionClass(name) succeeds.
    // Generator and Fiber are runtime concepts, not stored as PhpObject, but PHP exposes
    // them via Reflection. Empty methods table is fine - dispatch handles them separately.
    try vm.classes.put(a, "Generator", ClassDef{ .name = "Generator" });
    try vm.classes.put(a, "Fiber", ClassDef{ .name = "Fiber" });

    var rref_def = ClassDef{ .name = "ReflectionReference" };
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
    try vm.classes.put(a, "ReflectionGenerator", rg_def);
    try vm.native_fns.put(a, "ReflectionGenerator::__construct", rgConstruct);
    try vm.native_fns.put(a, "ReflectionGenerator::getExecutingLine", rgGetExecutingLine);
    try vm.native_fns.put(a, "ReflectionGenerator::getExecutingFile", rgGetExecutingFile);
    try vm.native_fns.put(a, "ReflectionGenerator::getFunction", rgGetFunction);
    try vm.native_fns.put(a, "ReflectionGenerator::getThis", rgGetThis);
    try vm.native_fns.put(a, "ReflectionGenerator::getExecutingGenerator", rgGetExecutingGenerator);
    try vm.native_fns.put(a, "ReflectionGenerator::getTrace", rgGetTrace);

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
}

fn rextConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len == 0 or args[0] != .string) return throwReflection(ctx, "ReflectionExtension::__construct() expects an extension name");
    const loaded = try ctx.vm.callByName("extension_loaded", args[0..1]);
    if (!loaded.isTruthy()) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Extension \"{s}\" does not exist", .{args[0].string.bytes()});
        try ctx.vm.strings.append(ctx.allocator, msg);
        return throwReflection(ctx, msg);
    }
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(try ctx.createString(args[0].string.bytes())) }) catch return error.OutOfMemory;
    return NativeResult.scalar(.null);
}

fn rextGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rextGetVersion(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal("8.4.1");
}

fn reflectionEmptyArray(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

fn reflectionTrue(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn rextInfo(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = this.get("name");
    if (name == .string) try ctx.vm.output.appendSlice(ctx.allocator, name.string.bytes());
    return NativeResult.scalar(.null);
}

fn rextToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return rextGetName(ctx, &.{});
}

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn throwReflection(ctx: *NativeContext, msg: []const u8) RuntimeError {
    // callers own msg lifetime. literal callers pass static strings safely;
    // heap callers must track msg in ctx.strings before invoking this
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
    try obj.set(ctx.allocator, "type_name", .{ .string = Value.String.borrowed(clean_name) });
    try obj.set(ctx.allocator, "nullable", .{ .bool = is_nullable });
    return obj;
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
        try obj.set(ctx.allocator, "type_str", .{ .string = Value.String.borrowed(clean) });
        if (has_null) is_nullable = true;
        try obj.set(ctx.allocator, "nullable", .{ .bool = is_nullable });
        try obj.set(ctx.allocator, "_self_class", .{ .string = Value.String.borrowed(self_class orelse "") });
        return obj;
    }
    if (std.mem.indexOfScalar(u8, clean, '&') != null) {
        const obj = try ctx.createObject("ReflectionIntersectionType");
        try obj.set(ctx.allocator, "type_str", .{ .string = Value.String.borrowed(clean) });
        return obj;
    }
    return createNamedTypeObj(ctx, clean, is_nullable);
}

fn buildMethodObj(ctx: *NativeContext, class_name: []const u8, method_name: []const u8, info: ClassDef.MethodInfo, declaring_class: []const u8) !*PhpObject {
    const obj = try ctx.createObject("ReflectionMethod");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(method_name) });
    try obj.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(class_name) });
    try obj.set(ctx.allocator, "_declaring_class", .{ .string = Value.String.borrowed(declaring_class) });
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
            break;
        }
        const cls = vm.classes.get(current) orelse break;
        current = cls.parent orelse break;
    }
    return declaring;
}

const PropertyDefResult = struct {
    prop: ClassDef.PropertyDef,
    declaring_class: []const u8,
    is_static: bool = false,
};

fn findPropertyDef(vm: *VM, class_name: []const u8, prop_name: []const u8) ?PropertyDefResult {
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = vm.classes.get(name) orelse break;
        for (cls.properties.items) |prop| {
            if (std.mem.eql(u8, prop.name, prop_name)) return .{ .prop = prop, .declaring_class = name };
        }
        if (cls.static_props.get(prop_name)) |v| {
            const synth: ClassDef.PropertyDef = .{ .name = prop_name, .default = v, .has_default = true };
            return .{ .prop = synth, .declaring_class = name, .is_static = true };
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

    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(prop.name) });
    try obj.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(class_name) });
    try obj.set(ctx.allocator, "_visibility", .{ .int = @intFromEnum(prop.visibility) });

    // PHP's ReflectionProperty::hasDefaultValue() always returns false for
    // constructor-promoted properties, even if the promoted parameter has
    // a default in the constructor signature.
    const effective_has_default = prop.has_default and !prop.is_promoted;

    try obj.set(ctx.allocator, "_has_default", .{ .bool = effective_has_default });
    try obj.set(
        ctx.allocator,
        "_default_value",
        if (effective_has_default) prop.default else .null,
    );

    try obj.set(ctx.allocator, "_declaring_class", .{ .string = Value.String.borrowed(declaring_class) });

    try obj.set(
        ctx.allocator,
        "_set_visibility",
        .{ .int = @intFromEnum(prop.set_visibility) },
    );
    try obj.set(
        ctx.allocator,
        "_has_set_visibility",
        .{ .bool = prop.has_set_visibility },
    );

    try obj.set(ctx.allocator, "_is_readonly", .{ .bool = prop.is_readonly });
    try obj.set(ctx.allocator, "_is_final", .{ .bool = prop.is_final });
    try obj.set(ctx.allocator, "_is_static", .{ .bool = is_static });

    return obj;
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
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ iface_name, method_name }) catch return false;
    if (vm.functions.get(key) != null or vm.native_fns.get(key) != null) return true;
    const iface = vm.interfaces.get(iface_name) orelse return false;
    for (iface.methods.items) |m| {
        if (std.mem.eql(u8, m, method_name)) return true;
    }
    return false;
}

fn rcConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return throwReflection(ctx, "ReflectionClass::__construct() expects a class name");
    const raw_class_name = if (args[0] == .string)
        args[0].string.bytes()
    else if (args[0] == .object)
        args[0].object.class_name
    else
        return throwReflection(ctx, "ReflectionClass::__construct() expects a class name or object");
    // PHP accepts leading-backslash on FQN class strings; normalize so the
    // class registry lookup succeeds either way
    const class_name = if (raw_class_name.len > 0 and raw_class_name[0] == '\\') raw_class_name[1..] else raw_class_name;
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);

    _ = resolveClassName(ctx.vm, class_name) catch {
        const msg = std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" does not exist", .{class_name}) catch return throwReflection(ctx, "Class does not exist");
        try ctx.strings.append(ctx.allocator, msg);
        return throwReflection(ctx, msg);
    };
    if (ctx.vm.classes.get(class_name) == null and ctx.vm.interfaces.get(class_name) == null and !ctx.vm.traits.contains(class_name)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" does not exist", .{class_name}) catch return throwReflection(ctx, "Class does not exist");
        try ctx.strings.append(ctx.allocator, msg);
        return throwReflection(ctx, msg);
    }

    const stable_name = try ctx.createString(class_name);
    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(stable_name) });
    try this.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(class_name) });
    try this.set(ctx.allocator, "_is_trait", .{ .bool = ctx.vm.traits.contains(class_name) });
    return NativeResult.scalar(.null);
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
    const is_iface = this.get("_is_interface");
    if (is_iface == .bool and is_iface.bool) return NativeResult.scalar(.{ .bool = false });
    const is_trait = this.get("_is_trait");
    if (is_trait == .bool and is_trait.bool) return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = true });
    if (cls.is_abstract) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = true });
}

fn rcGetParentClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    const parent_name = cls.parent orelse return NativeResult.scalar(.{ .bool = false });

    const parent_obj = try ctx.createObject("ReflectionClass");
    try parent_obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(parent_name) });
    try parent_obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(parent_name) });
    return NativeResult.borrowed(.{ .object = parent_obj });
}

fn rcImplementsInterface(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const iface_name = args[0].string.bytes();
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });

    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(ctx.allocator);
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        for (cls.interfaces.items) |iface| try queue.append(ctx.allocator, iface);
        current = cls.parent;
    }
    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const iface = queue.items[i];
        if (std.mem.eql(u8, iface, iface_name)) return NativeResult.scalar(.{ .bool = true });
        if (ctx.vm.classes.get(iface)) |idef| {
            for (idef.interfaces.items) |sub| try queue.append(ctx.allocator, sub);
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcIsInstance(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const obj_class = args[0].object.class_name;
    if (std.mem.eql(u8, obj_class, class_name)) return NativeResult.scalar(.{ .bool = true });
    if (ctx.vm.interfaces.contains(class_name)) {
        var current: ?[]const u8 = obj_class;
        while (current) |name| {
            const cls = ctx.vm.classes.get(name) orelse break;
            for (cls.interfaces.items) |iface| {
                if (std.mem.eql(u8, iface, class_name)) return NativeResult.scalar(.{ .bool = true });
            }
            current = cls.parent;
        }
        return NativeResult.scalar(.{ .bool = false });
    }
    var current: ?[]const u8 = obj_class;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.parent) |p| {
            if (std.mem.eql(u8, p, class_name)) return NativeResult.scalar(.{ .bool = true });
            current = p;
        } else break;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcIsSubclassOf(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const parent_name = args[0].string.bytes();
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        current = cls.parent;
        if (current) |p| {
            if (std.mem.eql(u8, p, parent_name)) return NativeResult.scalar(.{ .bool = true });
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcNewInstance(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (ctx.vm.interfaces.contains(class_name)) {
        const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot instantiate interface {s}", .{class_name});
        try ctx.strings.append(ctx.allocator, msg);
        try ctx.vm.setPendingException("Error", msg);
        return error.RuntimeError;
    }
    if (ctx.vm.classes.get(class_name)) |cd| {
        if (cd.is_abstract) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot instantiate abstract class {s}", .{class_name});
            try ctx.strings.append(ctx.allocator, msg);
            try ctx.vm.setPendingException("Error", msg);
            return error.RuntimeError;
        }
    }
    const obj = try ctx.vm.allocator.create(PhpObject);
    ctx.vm.next_object_id += 1;
    obj.* = .{ .class_name = class_name, .id = ctx.vm.next_object_id };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    // full slot layout + per-instance default copies (walks the parent chain,
    // deep-clones array defaults) - the raw cls.properties loop skipped both,
    // so inherited typed props read as uninitialized
    try ctx.vm.initObjectProperties(obj, class_name);
    if (ctx.vm.hasMethod(class_name, "__construct")) {
        _ = try ctx.callMethod(obj, "__construct", args);
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn rcNewInstanceArgs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (ctx.vm.classes.get(class_name)) |cd| {
        if (cd.is_abstract) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot instantiate abstract class {s}", .{class_name});
            try ctx.strings.append(ctx.allocator, msg);
            try ctx.vm.setPendingException("Error", msg);
            return error.RuntimeError;
        }
    }

    const arr = if (args.len >= 1 and args[0] == .array) args[0].array else return NativeResult.scalar(.null);

    var ctor_args: [16]Value = undefined;
    const count = @min(arr.entries.items.len, 16);
    for (0..count) |i| {
        ctor_args[i] = arr.entries.items[i].value;
    }

    const obj = try ctx.vm.allocator.create(PhpObject);
    ctx.vm.next_object_id += 1;
    obj.* = .{ .class_name = class_name, .id = ctx.vm.next_object_id };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);

    try ctx.vm.initObjectProperties(obj, class_name);

    if (ctx.vm.hasMethod(class_name, "__construct")) {
        _ = try ctx.callMethod(obj, "__construct", ctor_args[0..count]);
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn rcGetMethods(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const filter: ?i64 = if (args.len >= 1 and args[0] == .int) args[0].int else null;

    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);

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
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::getMethod() expects a method name");
    const method_name = args[0].string.bytes();
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    if (!ctx.vm.hasMethod(class_name, method_name)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Method {s}::{s}() does not exist", .{ class_name, method_name }) catch return error.OutOfMemory;
        try ctx.strings.append(ctx.allocator, msg);
        return throwReflection(ctx, msg);
    }

    const declaring = findDeclaringClass(ctx.vm, class_name, method_name);
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.null);
    const info = cls.methods.get(method_name) orelse ClassDef.MethodInfo{ .name = method_name, .arity = 0 };
    const obj = try buildMethodObj(ctx, class_name, method_name, info, declaring);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rcHasMethod(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    // PHP method names are case-insensitive
    if (ctx.vm.hasMethod(class_name, args[0].string.bytes())) return NativeResult.scalar(.{ .bool = true });
    var current: ?[]const u8 = class_name;
    while (current) |cn| {
        if (ctx.vm.classes.get(cn)) |cls| {
            var it = cls.methods.iterator();
            while (it.next()) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, args[0].string.bytes())) return NativeResult.scalar(.{ .bool = true });
            }
            current = cls.parent;
        } else break;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcIsAbstract(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const is_iface = this.get("_is_interface");
    if (is_iface == .bool and is_iface.bool) return NativeResult.scalar(.{ .bool = true });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = cls.is_abstract });
}

fn rcIsFinal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.is_enum) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = cls.is_final });
}

fn rcGetModifiers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP class modifier bitmask: IS_EXPLICIT_ABSTRACT=32, IS_IMPLICIT_ABSTRACT=16,
    // IS_FINAL=4, IS_READONLY=65536. these are used by ReflectionClass::getModifiers
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .int = 0 });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .int = 0 });
    var mods: i64 = 0;
    if (cls.is_abstract) mods |= 32;
    if (cls.is_final) mods |= 4;
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
    const is_iface = this.get("_is_interface");
    if (is_iface == .bool and is_iface.bool) return NativeResult.scalar(.{ .bool = false });
    const is_trait = this.get("_is_trait");
    if (is_trait == .bool and is_trait.bool) return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.{ .bool = true });
    if (cls.is_abstract) return NativeResult.scalar(.{ .bool = false });
    if (cls.is_enum) return NativeResult.scalar(.{ .bool = false });
    if (cls.methods.get("__clone")) |m| {
        if (m.visibility != .public) return NativeResult.scalar(.{ .bool = false });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn rcIsInterface(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const is_iface = this.get("_is_interface");
    return NativeResult.scalar(.{ .bool = is_iface == .bool and is_iface.bool });
}

fn rcIsAnonymous(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = this.get("name");
    if (name != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = std.mem.startsWith(u8, name.string.bytes(), "class@anonymous") });
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
    var queue = std.ArrayListUnmanaged([]const u8){};
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

        const refobj = try ctx.createObject("ReflectionClass");
        try refobj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(iface) });
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
            const refobj = try ctx.createObject("ReflectionClass");
            try refobj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(tname) });
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
    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(ctx.allocator);

    // PHP's order: parent class interfaces first, then own, with each interface
    // immediately followed by its transitively-extended parents
    // (IteratorAggregate -> Traversable). collect parent->child chain first
    var chain = std.ArrayListUnmanaged([]const u8){};
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

fn buildReflectionAttribute(ctx: *NativeContext, attr: AttributeDef, target: i64, is_repeated: bool) RuntimeError!Value {
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
    try obj.set(ctx.allocator, "_arguments", .{ .array = args_arr });
    try obj.set(ctx.allocator, "_target", .{ .int = target });
    try obj.set(ctx.allocator, "_is_repeated", .{ .bool = is_repeated });
    return .{ .object = obj };
}

// IS_INSTANCEOF = 2 in PHP's ReflectionAttribute constants. When set, the
// filter matches any attribute whose class extends/implements the given name.
const REFLECTION_ATTRIBUTE_IS_INSTANCEOF: i64 = 2;

fn buildAttributeArray(ctx: *NativeContext, attrs: []const AttributeDef, filter: ?[]const u8, target: i64) RuntimeError!NativeResult {
    return buildAttributeArrayWithFlags(ctx, attrs, filter, target, 0);
}

fn buildAttributeArrayWithFlags(ctx: *NativeContext, attrs: []const AttributeDef, filter: ?[]const u8, target: i64, flags: i64) RuntimeError!NativeResult {
    const arr = try ctx.createArray();
    for (attrs) |attr| {
        if (filter) |f| {
            if (flags & REFLECTION_ATTRIBUTE_IS_INSTANCEOF != 0) {
                // ensure the attribute's class is loaded so isInstanceOf can
                // walk its parent chain. PHP-side `class_exists()` triggers
                // autoload implicitly; here we have to drive it ourselves
                if (!ctx.vm.classes.contains(attr.name)) {
                    ctx.vm.tryAutoload(attr.name) catch {};
                }
                if (!ctx.vm.classes.contains(f)) {
                    ctx.vm.tryAutoload(f) catch {};
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
        try arr.append(ctx.allocator, try buildReflectionAttribute(ctx, attr, target, count > 1));
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.doc_comment.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, cls.doc_comment);
}

fn rmGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const func = rmLookupFunc(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.doc_comment.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, func.doc_comment);
}

fn rfGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
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
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, cls.attributes.items, filter, 1, flags);
}

fn rcGetProperties(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const filter: i64 = if (args.len >= 1 and args[0] == .int) args[0].int else 0;

    const arr = try ctx.createArray();
    var seen = std.StringHashMapUnmanaged(void){};
    defer seen.deinit(ctx.allocator);

    var is_own = true;
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        for (cls.properties.items) |prop| {
            if (!is_own and prop.visibility == .private) continue;
            if (!matchPropFilter(filter, prop.visibility, false)) continue;
            if (!seen.contains(prop.name)) {
                try seen.put(ctx.allocator, prop.name, {});
                const obj = try buildPropertyObj(ctx, class_name, prop, name);
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        }
        var sp_iter = cls.static_props.iterator();
        while (sp_iter.next()) |entry| {
            const sp_name = entry.key_ptr.*;
            if (cls.constant_names.contains(sp_name)) continue;
            const vis: ClassDef.Visibility = cls.const_visibility.get(sp_name) orelse .public;
            if (!is_own and vis == .private) continue;
            if (!matchPropFilter(filter, vis, true)) continue;
            if (!seen.contains(sp_name)) {
                try seen.put(ctx.allocator, sp_name, {});
                const pdef = ClassDef.PropertyDef{
                    .name = sp_name,
                    .default = entry.value_ptr.*,
                    .has_default = true,
                    .visibility = vis,
                    .type_str = cls.static_prop_types.get(sp_name) orelse "",
                };
                const obj = try buildPropertyObj(ctx, class_name, pdef, name);
                try obj.set(ctx.allocator, "_is_static", .{ .bool = true });
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        }
        if (ctx.vm.interfaces.contains(name)) {
            try appendInterfaceProperties(ctx, class_name, name, filter, arr, &seen);
        }
        current = cls.parent;
        is_own = false;
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn appendInterfaceProperties(ctx: *NativeContext, reflected: []const u8, name: []const u8, filter: i64, arr: *PhpArray, seen: *std.StringHashMapUnmanaged(void)) RuntimeError!void {
    const iface = ctx.vm.interfaces.get(name) orelse return;
    for (iface.parents.items) |parent| {
        const cls = ctx.vm.classes.get(parent) orelse continue;
        for (cls.properties.items) |prop| {
            if (seen.contains(prop.name) or !matchPropFilter(filter, prop.visibility, false)) continue;
            try seen.put(ctx.allocator, prop.name, {});
            const obj = try buildPropertyObj(ctx, reflected, prop, parent);
            try arr.append(ctx.allocator, .{ .object = obj });
        }
        try appendInterfaceProperties(ctx, reflected, parent, filter, arr, seen);
    }
}

fn matchPropFilter(filter: i64, vis: ClassDef.Visibility, is_static: bool) bool {
    if (filter == 0) return true;
    const IS_STATIC: i64 = 16;
    const IS_PUBLIC: i64 = 1;
    const IS_PROTECTED: i64 = 2;
    const IS_PRIVATE: i64 = 4;
    const IS_READONLY: i64 = 128;
    _ = IS_READONLY;
    const want_static = (filter & IS_STATIC) != 0;
    const want_public = (filter & IS_PUBLIC) != 0;
    const want_protected = (filter & IS_PROTECTED) != 0;
    const want_private = (filter & IS_PRIVATE) != 0;
    const any_vis = want_public or want_protected or want_private;
    const has_vis_match = (vis == .public and want_public) or
        (vis == .protected and want_protected) or
        (vis == .private and want_private);
    if (any_vis and !has_vis_match) return false;
    if (want_static and !is_static) return false;
    return true;
}

fn rcGetProperty(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::getProperty() expects a property name");
    const prop_name = args[0].string.bytes();
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    if (findPropertyDef(ctx.vm, class_name, prop_name)) |result| {
        const obj = try buildPropertyObjStatic(ctx, class_name, result.prop, result.declaring_class, result.is_static);
        return NativeResult.borrowed(.{ .object = obj });
    }
    const msg = std.fmt.allocPrint(ctx.allocator, "Property {s}::${s} does not exist", .{ class_name, prop_name }) catch return error.OutOfMemory;
    try ctx.strings.append(ctx.allocator, msg);
    return throwReflection(ctx, msg);
}

fn rcHasProperty(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = findPropertyDef(ctx.vm, class_name, args[0].string.bytes()) != null });
}

fn rcNewLazyProxy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const result = try rcNewLazyGhost(ctx, args);
    if (result.value == .object) result.value.object.lazy.?.proxy = true;
    return result;
}

fn rcNewLazyGhost(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const obj = try ctx.vm.allocator.create(PhpObject);
    // the lazy object owns its initializer until it runs or is cleared
    VM.retainValue(args[0]);
    obj.* = .{ .class_name = class_name };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);
    try ctx.vm.initObjectProperties(obj, class_name);
    const state = try ctx.allocator.create(PhpObject.LazyState);
    const count = if (obj.slots) |slots| slots.len else 0;
    state.* = .{ .initializer = args[0], .pending = try ctx.allocator.alloc(bool, count), .skip_serialize = args.len > 1 and args[1] == .int and (args[1].int & 8) != 0 };
    @memset(state.pending, true);
    obj.lazy = state;
    ctx.vm.next_object_id += 1;
    obj.id = ctx.vm.next_object_id;
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

    const obj = try ctx.vm.allocator.create(PhpObject);
    ctx.vm.next_object_id += 1;
    obj.* = .{ .class_name = class_name, .id = ctx.vm.next_object_id };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);

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
    const v = this.get("_is_trait");
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

fn rcGetConstants(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const arr = try ctx.createArray();
    var is_own = true;
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constant_order.items.len > 0) {
            for (cls.constant_order.items) |cname| {
                // private constants do not propagate to subclasses
                if (!is_own) {
                    const vis = cls.const_visibility.get(cname) orelse ClassDef.Visibility.public;
                    if (vis == .private) continue;
                }
                if (cls.static_props.get(cname)) |val| {
                    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(cname) }, val);
                }
            }
        } else {
            var it = cls.constant_names.iterator();
            while (it.next()) |entry| {
                if (!is_own) {
                    const vis = cls.const_visibility.get(entry.key_ptr.*) orelse ClassDef.Visibility.public;
                    if (vis == .private) continue;
                }
                if (cls.static_props.get(entry.key_ptr.*)) |val| {
                    try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(entry.key_ptr.*) }, val);
                }
            }
        }
        current = cls.parent;
        is_own = false;
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetReflectionConstants(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const arr = try ctx.createArray();
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constant_order.items.len > 0) {
            for (cls.constant_order.items) |cname| {
                if (cls.static_props.get(cname)) |val| {
                    const obj = try buildReflectionClassConstant(ctx, name, cname, val);
                    try arr.append(ctx.allocator, obj);
                }
            }
        } else {
            var it = cls.constant_names.iterator();
            while (it.next()) |entry| {
                const cname = entry.key_ptr.*;
                if (cls.static_props.get(cname)) |val| {
                    const obj = try buildReflectionClassConstant(ctx, name, cname, val);
                    try arr.append(ctx.allocator, obj);
                }
            }
        }
        current = cls.parent;
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetReflectionConstant(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const target = args[0].string.bytes();

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constant_names.contains(target)) {
            if (cls.static_props.get(target)) |val| {
                return NativeResult.borrowed(try buildReflectionClassConstant(ctx, name, target, val));
            }
        }
        current = cls.parent;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcHasConstant(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const target = args[0].string.bytes();

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constant_names.contains(target)) return NativeResult.scalar(.{ .bool = true });
        current = cls.parent;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcGetConstant(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (args.len == 0 or args[0] != .string) return NativeResult.scalar(.{ .bool = false });
    const target = args[0].string.bytes();

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constant_names.contains(target)) {
            if (cls.static_props.get(target)) |val| return NativeResult.share(val);
        }
        current = cls.parent;
    }
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

fn findConstantOwner(ctx: *NativeContext, class_name: []const u8, name: []const u8, depth: usize) ?[]const u8 {
    if (depth >= 256) return null;
    if (ctx.vm.trait_constants.get(class_name)) |constants| {
        for (constants) |constant| {
            if (std.mem.eql(u8, constant.name, name)) return class_name;
        }
    }
    if (ctx.vm.classes.get(class_name)) |cls| {
        if (cls.constant_names.contains(name)) return class_name;
        if (cls.parent) |parent| {
            if (findConstantOwner(ctx, parent, name, depth + 1)) |owner| return owner;
        }
        for (cls.interfaces.items) |interface| {
            if (findConstantOwner(ctx, interface, name, depth + 1)) |owner| return owner;
        }
    }
    return null;
}

fn findConstantDoc(ctx: *NativeContext, class_name: []const u8, name: []const u8, depth: usize) ?[]const u8 {
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
        if (cls.static_props.get(const_name)) |val| return NativeResult.share(val);
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
    const rc = try ctx.createObject("ReflectionClass");
    try rc.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(class_name) });
    return NativeResult.borrowed(.{ .object = rc });
}

fn rccConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return throwReflection(ctx, "ReflectionClassConstant::__construct expects class and constant name");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const raw_class: []const u8 = switch (args[0]) {
        .string => args[0].string.bytes(),
        .object => args[0].object.class_name,
        else => return throwReflection(ctx, "ReflectionClassConstant::__construct class must be a string or object"),
    };
    const class_name = if (raw_class.len > 0 and raw_class[0] == '\\') raw_class[1..] else raw_class;
    if (args[1] != .string) return throwReflection(ctx, "ReflectionClassConstant::__construct constant name must be a string");
    const const_name = args[1].string.bytes();
    try ctx.vm.tryAutoload(class_name);
    const owner = findConstantOwner(ctx, class_name, const_name, 0) orelse return throwReflection(ctx, "Constant not found");
    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(const_name) });
    try this.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(owner) });
    return NativeResult.scalar(.null);
}

fn rccGetAttributes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.null);
    const const_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const cls = ctx.vm.classes.get(class_name) orelse {
        return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    };
    if (cls.constant_attributes.get(const_name)) |attrs| {
        return try buildAttributeArray(ctx, attrs, null, 16);
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
            if (cls.static_prop_types.get(const_name)) |type_str| {
                if (cls.constant_names.contains(const_name)) {
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
            if (cls.static_prop_types.get(const_name) != null and cls.constant_names.contains(const_name)) return NativeResult.scalar(.{ .bool = true });
            current = cls.parent;
        } else break;
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rcIsInternal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = isInternalClassName(name_v.string.bytes()) });
}

fn rcIsUserDefined(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = !isInternalClassName(name_v.string.bytes()) });
}

// hard-coded list of built-in PHP classes zphp ships natively. used by
// ReflectionClass::isInternal/isUserDefined. covers everything registered
// from src/stdlib/*.zig at VM init time so a user-declared class with the
// same name is not mistakenly flagged
fn isInternalClassName(name: []const u8) bool {
    return @import("builtin_classes.zig").contains(name);
}

fn rcGetFileName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.file_path.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, cls.file_path);
}

fn rcGetStartLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.start_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(cls.start_line) });
}

fn rcGetEndLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(name) orelse return NativeResult.scalar(.{ .bool = false });
    if (cls.end_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(cls.end_line) });
}

fn rcGetDefaultProperties(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
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
    const arr = try ctx.createArray();
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        var it = cls.static_props.iterator();
        while (it.next()) |entry| {
            if (cls.constant_names.contains(entry.key_ptr.*)) continue;
            try arr.set(ctx.allocator, .{ .string = Value.String.borrowed(entry.key_ptr.*) }, entry.value_ptr.*);
        }
        current = cls.parent;
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rcGetStaticPropertyValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::getStaticPropertyValue() expects a property name");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const prop_name = args[0].string.bytes();
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (!cls.constant_names.contains(prop_name)) {
            if (cls.static_props.get(prop_name)) |v| return NativeResult.share(v);
        }
        current = cls.parent;
    }
    if (args.len >= 2) return NativeResult.share(args[1]);
    return throwReflection(ctx, "Static property does not exist");
}

fn rcSetStaticPropertyValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::setStaticPropertyValue() expects a property name and value");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const prop_name = args[0].string.bytes();
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls_ptr = ctx.vm.classes.getPtr(name) orelse break;
        if (!cls_ptr.constant_names.contains(prop_name)) {
            if (cls_ptr.static_props.contains(prop_name)) {
                try cls_ptr.static_props.put(ctx.vm.allocator, prop_name, args[1]);
                return NativeResult.scalar(.null);
            }
        }
        current = cls_ptr.parent;
    }
    return throwReflection(ctx, "Static property does not exist");
}

fn rmConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return throwReflection(ctx, "ReflectionMethod::__construct() expects parameters");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);

    var class_name: []const u8 = undefined;
    var method_name: []const u8 = undefined;

    if (args.len >= 2 and args[1] == .string) {
        method_name = args[1].string.bytes();
        if (args[0] == .string) {
            class_name = args[0].string.bytes();
        } else if (args[0] == .object) {
            class_name = args[0].object.class_name;
        } else {
            return throwReflection(ctx, "ReflectionMethod::__construct() expects a class name or object");
        }
    } else if (args[0] == .string) {
        const s = args[0].string.bytes();
        if (std.mem.indexOf(u8, s, "::")) |sep| {
            class_name = s[0..sep];
            method_name = s[sep + 2 ..];
        } else {
            return throwReflection(ctx, "ReflectionMethod::__construct() expects Class::method format");
        }
    } else {
        return throwReflection(ctx, "ReflectionMethod::__construct() expects a class name or object");
    }
    if (class_name.len > 0 and class_name[0] == '\\') class_name = class_name[1..];

    if (!ctx.vm.hasMethod(class_name, method_name)) {
        // class might not be loaded yet - try autoloading
        if (ctx.vm.classes.get(class_name) == null and ctx.vm.interfaces.get(class_name) == null) {
            try ctx.vm.tryAutoload(class_name);
        }
        if (!ctx.vm.hasMethod(class_name, method_name) and
            !hasInterfaceMethod(ctx.vm, class_name, method_name) and
            !hasAbstractMethodInChain(ctx.vm, class_name, method_name))
        {
            const msg = std.fmt.allocPrint(ctx.allocator, "Method {s}::{s}() does not exist", .{ class_name, method_name }) catch return error.OutOfMemory;
            try ctx.strings.append(ctx.allocator, msg);
            return throwReflection(ctx, msg);
        }
    }

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

    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(method_name) });
    try this.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(class_name) });
    try this.set(ctx.allocator, "_declaring_class", .{ .string = Value.String.borrowed(declaring) });
    try this.set(ctx.allocator, "_is_static", .{ .bool = info.is_static });
    try this.set(ctx.allocator, "_visibility", .{ .int = @intFromEnum(info.visibility) });

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return NativeResult.scalar(.null);
    if (ctx.vm.functions.get(key)) |func| {
        try this.set(ctx.allocator, "_arity", .{ .int = func.arity });
        try this.set(ctx.allocator, "_required_params", .{ .int = func.required_params });
    } else {
        try this.set(ctx.allocator, "_arity", .{ .int = info.arity });
        try this.set(ctx.allocator, "_required_params", .{ .int = info.arity });
    }

    return NativeResult.scalar(.null);
}

fn rmGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rmLookupFunc(ctx: *NativeContext) ?@TypeOf(ctx.vm.functions.get("").?) {
    const this = getThis(ctx) orelse return null;
    const method_name = methodLookupName(this) orelse return null;
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return null;
    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return null;
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
    const dc = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = isInternalClassName(dc) });
}

fn rmIsUserDefined(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const dc = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = !isInternalClassName(dc) });
}

fn reflectionEmptyString(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal("");
}

fn rmGetParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.null);

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return NativeResult.scalar(.null);
    const func = ctx.vm.functions.get(key) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    const result = try buildParamArray(ctx, func, key);
    if (this.get("_hook_method") == .string and result == .array) {
        for (result.array.entries.items) |entry| {
            if (entry.value == .object) try entry.value.object.set(ctx.allocator, "_hook_declaring_function", .{ .object = this });
        }
    }
    return NativeResult.borrowed(result);
}

fn rmIsPublic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("_visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 0 });
}

fn rmIsProtected(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("_visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 1 });
}

fn rmIsPrivate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("_visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 2 });
}

fn rmIsStatic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const is_static = this.get("_is_static");
    return NativeResult.scalar(.{ .bool = is_static == .bool and is_static.bool });
}

fn rmGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.null);

    const obj = try ctx.createObject("ReflectionClass");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(declaring) });
    try obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(declaring) });
    return NativeResult.borrowed(.{ .object = obj });
}

fn rmGetReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const hook_type = this.get("_hook_return_type");
    if (hook_type == .string) {
        if (hook_type.string.bytes().len == 0) return NativeResult.scalar(.null);
        return NativeResult.borrowed(.{ .object = try createTypeObj(ctx, hook_type.string.bytes(), false, this.get("_declaring_class").string.bytes()) });
    }
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.null);

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return NativeResult.scalar(.null);
    const type_info = vm_mod.getTypeInfo(key) orelse return NativeResult.scalar(.null);
    if (type_info.return_type.len == 0) return NativeResult.scalar(.null);

    const obj = try createTypeObj(ctx, type_info.return_type, false, declaring);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rmHasReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const hook_type = this.get("_hook_return_type");
    if (hook_type == .string) {
        return NativeResult.scalar(.{ .bool = hook_type.string.bytes().len > 0 });
    }
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .bool = false });
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return NativeResult.scalar(.{ .bool = false });
    const type_info = vm_mod.getTypeInfo(key) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = type_info.return_type.len > 0 });
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
    const arity = this.get("_arity");
    return if (arity == .int) NativeResult.share(arity) else NativeResult.scalar(.{ .int = 0 });
}

fn rmGetNumberOfRequiredParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const req = this.get("_required_params");
    return if (req == .int) NativeResult.share(req) else NativeResult.scalar(.{ .int = 0 });
}

fn rpGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rpGetType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const type_val = this.get("_type_name");
    if (type_val != .string or type_val.string.bytes().len == 0) return NativeResult.scalar(.null);

    const nullable = this.get("_nullable");
    var is_nullable = nullable == .bool and nullable.bool;
    // PHP's implicit-nullable: `foo($x = null)` reports the type as nullable
    // even though source didn't write '?'. detect by checking default == null
    const has_default = this.get("_has_default");
    if (!is_nullable and has_default == .bool and has_default.bool) {
        if (this.get("_default_value") == .null) is_nullable = true;
    }
    const declaring = this.get("_declaring_class");
    const self_class: ?[]const u8 = if (declaring == .string and declaring.string.bytes().len > 0) declaring.string.bytes() else null;
    const obj = try createTypeObj(ctx, type_val.string.bytes(), is_nullable, self_class);
    return NativeResult.borrowed(.{ .object = obj });
}

fn rpIsDefaultValueAvailable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const has_default = this.get("_has_default");
    return NativeResult.scalar(.{ .bool = has_default == .bool and has_default.bool });
}

fn rpGetDefaultValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const has_default = this.get("_has_default");
    if (has_default != .bool or !has_default.bool) return throwReflection(ctx, "Internal error: no default value available");
    return NativeResult.share(this.get("_default_value"));
}

fn rpIsOptional(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const has_default = this.get("_has_default");
    if (has_default == .bool and has_default.bool) return NativeResult.scalar(.{ .bool = true });
    const is_var = this.get("_is_variadic");
    return NativeResult.scalar(.{ .bool = is_var == .bool and is_var.bool });
}

fn rpGetPosition(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.share(this.get("_position"));
}

fn rpAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const type_val = this.get("_type_name");
    if (type_val != .string or type_val.string.bytes().len == 0) return NativeResult.scalar(.{ .bool = true });
    if (std.mem.eql(u8, type_val.string.bytes(), "mixed") or std.mem.eql(u8, type_val.string.bytes(), "null")) return NativeResult.scalar(.{ .bool = true });
    const nullable = this.get("_nullable");
    return NativeResult.scalar(.{ .bool = nullable == .bool and nullable.bool });
}

fn rpIsPassedByReference(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const by_ref = this.get("_by_reference");
    return NativeResult.scalar(.{ .bool = by_ref == .bool and by_ref.bool });
}

fn rpCanBePassedByValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const by_ref = this.get("_by_reference");
    return NativeResult.scalar(.{ .bool = !(by_ref == .bool and by_ref.bool) });
}

fn rpHasType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const type_val = this.get("_type_name");
    return NativeResult.scalar(.{ .bool = type_val == .string and type_val.string.bytes().len > 0 });
}

// constant default sentinel: "\x00CC\x00<class>\x00<const>" (class empty for global constants)
// returns "CONST" for global, "Class::CONST" for class constants
fn decodeConstSentinel(ctx: *NativeContext, v: Value) !?[]const u8 {
    if (v != .string) return null;
    const s = v.string.bytes();
    if (s.len <= 4 or s[0] != 0 or s[1] != 'C' or s[2] != 'C' or s[3] != 0) return null;
    const rest = s[4..];
    const sep = std.mem.indexOfScalar(u8, rest, 0) orelse return null;
    const class_name = rest[0..sep];
    const const_name = rest[sep + 1 ..];
    if (class_name.len == 0) return const_name;
    const joined = try std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ class_name, const_name });
    try ctx.strings.append(ctx.allocator, joined);
    return joined;
}

fn rpIsDefaultValueConstant(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const has_default = this.get("_has_default");
    if (has_default != .bool or !has_default.bool) return NativeResult.scalar(.{ .bool = false });
    const name = this.get("_default_const_name");
    return NativeResult.scalar(.{ .bool = name == .string and name.string.bytes().len > 0 });
}

fn rpGetDefaultValueConstantName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const has_default = this.get("_has_default");
    if (has_default != .bool or !has_default.bool) return throwReflection(ctx, "Internal error: no default value available");
    const name = this.get("_default_const_name");
    if (name == .string and name.string.bytes().len > 0) return NativeResult.share(name);
    return NativeResult.scalar(.null);
}

fn rpGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const param_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const class_name = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const method_name = if (this.get("_method_name") == .string) this.get("_method_name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    var key_buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{s}:{s}", .{ method_name, param_name }) catch return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const attrs = cls.param_attributes.get(key) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });

    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 32, flags);
}

fn rpGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const declaring = this.get("_declaring_class");
    if (declaring != .string or declaring.string.bytes().len == 0) return NativeResult.scalar(.null);

    const obj = try ctx.createObject("ReflectionClass");
    try obj.set(ctx.allocator, "name", declaring);
    try obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(declaring.string.bytes()) });
    return NativeResult.borrowed(.{ .object = obj });
}

fn rpIsVariadic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = this.get("_is_variadic");
    return NativeResult.scalar(.{ .bool = v == .bool and v.bool });
}

fn rpGetDeclaringFunction(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const hook = this.get("_hook_declaring_function");
    if (hook == .object) return NativeResult.share(hook);
    const func_name = if (this.get("_function") == .string) this.get("_function").string.bytes() else "";
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else "";
    if (declaring.len > 0) {
        const obj = try ctx.createObject("ReflectionMethod");
        try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(func_name) });
        try obj.set(ctx.allocator, "_declaring_class", .{ .string = Value.String.borrowed(declaring) });
        return NativeResult.borrowed(.{ .object = obj });
    }
    const obj = try ctx.createObject("ReflectionFunction");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(func_name) });
    return NativeResult.borrowed(.{ .object = obj });
}

fn rntGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("type_name"));
}

fn rntToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name_v = this.get("type_name");
    if (name_v != .string) return NativeResult.share(name_v);
    const nullable_v = this.get("nullable");
    const is_nullable = nullable_v == .bool and nullable_v.bool;
    if (!is_nullable or std.mem.eql(u8, name_v.string.bytes(), "mixed") or std.mem.eql(u8, name_v.string.bytes(), "null")) return NativeResult.share(name_v);
    const result = std.fmt.allocPrint(ctx.allocator, "?{s}", .{name_v.string.bytes()}) catch return NativeResult.share(name_v);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn rntIsBuiltin(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = this.get("type_name");
    if (name != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = isBuiltinType(name.string.bytes()) });
}

fn rntAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const nullable = this.get("nullable");
    if (nullable == .bool and nullable.bool) return NativeResult.scalar(.{ .bool = true });
    // mixed and null types implicitly allow null
    const tn = this.get("type_name");
    if (tn == .string) {
        if (std.mem.eql(u8, tn.string.bytes(), "mixed") or std.mem.eql(u8, tn.string.bytes(), "null")) {
            return NativeResult.scalar(.{ .bool = true });
        }
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rutGetTypes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const ts_v = this.get("type_str");
    if (ts_v != .string) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const sc_v = this.get("_self_class");
    const self_class: ?[]const u8 = if (sc_v == .string and sc_v.string.bytes().len > 0) sc_v.string.bytes() else null;
    const arr = try ctx.createArray();
    var it = std.mem.splitScalar(u8, ts_v.string.bytes(), '|');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const obj = try createNamedTypeObj(ctx, part, false);
        if (self_class) |sc| {
            if (std.mem.eql(u8, part, "self")) {
                try obj.set(ctx.allocator, "type_name", .{ .string = Value.String.borrowed(sc) });
            }
        }
        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return NativeResult.borrowed(.{ .array = arr });
}

fn rutAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const nullable = this.get("nullable");
    return NativeResult.scalar(.{ .bool = nullable == .bool and nullable.bool });
}

fn rutToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const ts_v = this.get("type_str");
    return NativeResult.share(ts_v);
}

fn ritGetTypes(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const ts_v = this.get("type_str");
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
    const ts_v = this.get("type_str");
    return NativeResult.share(ts_v);
}

fn rfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return throwReflection(ctx, "ReflectionFunction::__construct() expects a function name");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);

    if (args[0] == .object and std.mem.eql(u8, args[0].object.class_name, "Closure")) {
        const callable = args[0].object.get("__callable");
        if (callable == .string) {
            try this.set(ctx.allocator, "name", callable);
        } else if (callable == .array and callable.array.entries.items.len == 2 and callable.array.entries.items[1].value == .string) {
            const target = callable.array.entries.items[0].value;
            const method = callable.array.entries.items[1].value.string.bytes();
            const class_name = if (target == .object) target.object.class_name else if (target == .string) target.string.bytes() else "";
            const full = std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ class_name, method }) catch return NativeResult.scalar(.null);
            try ctx.strings.append(ctx.allocator, full);
            try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(full) });
            try this.set(ctx.allocator, "__is_method_ref", .{ .bool = true });
            if (target == .object) try this.set(ctx.allocator, "__scope_class", .{ .string = Value.String.borrowed(class_name) });
        } else return throwReflection(ctx, "ReflectionFunction::__construct() expects a function name");
    } else if (args[0] == .string) {
        const raw_name = args[0].string.bytes();
        const func_name = if (raw_name.len > 0 and raw_name[0] == '\\') raw_name[1..] else raw_name;
        if (ctx.vm.functions.get(func_name) == null and ctx.vm.native_fns.get(func_name) == null)
            return throwReflection(ctx, "Function does not exist");
        // a closure instance name keeps the closure alive while reflected
        const name_value: Value = if (args[0] == .string and std.mem.startsWith(u8, func_name, "__closure_")) args[0] else .{ .string = Value.String.borrowed(func_name) };
        try this.set(ctx.allocator, "name", name_value);
        // closures created inside a class method inherit that class as their scope
        if (std.mem.startsWith(u8, func_name, "__closure_")) {
            if (ctx.vm.closureScopeByName(func_name)) |scope| {
                try this.set(ctx.allocator, "__scope_class", .{ .string = Value.String.borrowed(scope) });
            }
        }
    } else if (args[0] == .array) {
        // array callable [$obj, 'method'] - store as method reference
        const arr = args[0].array;
        if (arr.entries.items.len == 2 and arr.entries.items[1].value == .string) {
            const method = arr.entries.items[1].value.string.bytes();
            const target = arr.entries.items[0].value;
            const class_name = if (target == .object) target.object.class_name else if (target == .string) target.string.bytes() else "";
            const full = std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ class_name, method }) catch return NativeResult.scalar(.null);
            try ctx.strings.append(ctx.allocator, full);
            try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(full) });
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

fn rfInvoke(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fn_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callByName(fn_name, args));
}

fn rfInvokeArgs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fn_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .array) return NativeResult.scalar(.null);
    const arr = args[0].array;
    var call_args: [16]Value = undefined;
    const count = @min(arr.entries.items.len, 16);
    for (0..count) |i| call_args[i] = arr.entries.items[i].value;
    return NativeResult.share(try ctx.vm.callByName(fn_name, call_args[0..count]));
}

fn rfGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rfGetParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const func_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const func = ctx.vm.functions.get(func_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    return NativeResult.borrowed(try buildParamArray(ctx, func, func_name));
}

fn rfGetReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const func_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);

    const type_info = closureAwareTypeInfo(func_name) orelse return NativeResult.scalar(.null);
    if (type_info.return_type.len == 0) return NativeResult.scalar(.null);

    const obj = try createTypeObj(ctx, type_info.return_type, false, null);
    return NativeResult.borrowed(.{ .object = obj });
}

fn closureAwareTypeInfo(func_name: []const u8) ?@TypeOf(vm_mod.getTypeInfo("").?) {
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
    const func_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });

    const type_info = closureAwareTypeInfo(func_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = type_info.return_type.len > 0 });
}

fn rfGetNumberOfParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const func_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .int = 0 });
    const func = ctx.vm.functions.get(func_name) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = func.arity });
}

fn rfGetNumberOfRequiredParameters(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const func_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .int = 0 });
    const func = ctx.vm.functions.get(func_name) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = func.required_params });
}

// internal builtins (registered in vm.native_fns) have no file/line. user-
// defined functions live in vm.functions and carry the source path on their
// ObjFunction. start line comes from the first instruction's stored line
fn rfGetFileName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(name_v.string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.file_path.len == 0) return NativeResult.scalar(.{ .bool = false });
    return try NativeResult.copyString(ctx.allocator, func.file_path);
}

fn rfGetStartLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(name_v.string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    if (func.start_line == 0) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .int = @intCast(func.start_line) });
}

fn rfGetEndLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
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
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = std.mem.startsWith(u8, name, "__closure_") });
}

fn rfIsInternal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // built-in native functions register in vm.native_fns. user functions
    // land in vm.functions. closures sit under __closure_ keys which are
    // also user-defined
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
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
    const func_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(func_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.is_generator });
}

fn rfIsVariadic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(func_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.is_variadic });
}

fn rfGetClosureUsedVariables(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const fn_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const result = try ctx.createArray();
    for (ctx.vm.captures.items) |cap| {
        if (std.mem.eql(u8, cap.closure_name, fn_name)) {
            const name = if (cap.var_name.len > 0 and cap.var_name[0] == '$') cap.var_name[1..] else cap.var_name;
            if (std.mem.eql(u8, name, "this")) continue;
            const val = if (cap.ref_cell) |rc| rc.* else cap.value;
            try result.set(ctx.allocator, .{ .string = Value.String.borrowed(name) }, val);
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn rfGetClosureCalledClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (this.get("__scope_class") == .string) {
        const scope_name = this.get("__scope_class").string.bytes();
        const obj = try ctx.createObject("ReflectionClass");
        try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(scope_name) });
        return NativeResult.borrowed(.{ .object = obj });
    }
    return NativeResult.scalar(.null);
}

fn rfGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const func_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const compile_name = ctx.vm.getOrigClosureName(func_name);
    const attrs = ctx.vm.function_attributes.get(compile_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 2, flags);
}

fn rfGetClosureScopeClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (this.get("__scope_class") == .string) {
        const scope_name = this.get("__scope_class").string.bytes();
        const obj = try ctx.createObject("ReflectionClass");
        try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(scope_name) });
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (ctx.vm.closureScopeByName(name)) |scope| {
        const obj = try ctx.createObject("ReflectionClass");
        try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(scope) });
        return NativeResult.borrowed(.{ .object = obj });
    }
    return NativeResult.scalar(.null);
}

fn rfGetClosureThis(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    return NativeResult.share(ctx.vm.closureThisByName(name));
}

fn rfIsStatic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    _ = ctx;
    // a "static" closure is one declared with `static function` keyword.
    // zphp does not track this flag separately; reporting false matches PHP
    // for ordinary closures and is a known nuance for `static fn` declarations.
    return NativeResult.scalar(.{ .bool = false });
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
    const type_info = vm_mod.getTypeInfo(effective_key) orelse vm_mod.getTypeInfo(type_key);

    const param_name = func.params[i];
    const clean_name = if (param_name.len > 0 and param_name[0] == '$') param_name[1..] else param_name;
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(clean_name) });
    try obj.set(ctx.allocator, "_position", .{ .int = @intCast(i) });

    if (type_info) |ti| {
        if (i < ti.param_types.len and ti.param_types[i].len > 0) {
            const raw_type = ti.param_types[i];
            if (raw_type[0] == '?') {
                try obj.set(ctx.allocator, "_type_name", .{ .string = Value.String.borrowed(raw_type[1..]) });
                try obj.set(ctx.allocator, "_nullable", .{ .bool = true });
            } else {
                try obj.set(ctx.allocator, "_type_name", .{ .string = Value.String.borrowed(raw_type) });
                try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
            }
        } else {
            try obj.set(ctx.allocator, "_type_name", .{ .string = Value.String.borrowed("") });
            try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
        }
    } else {
        try obj.set(ctx.allocator, "_type_name", .{ .string = Value.String.borrowed("") });
        try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
    }

    const is_variadic = func.is_variadic and i == func.arity - 1;
    try obj.set(ctx.allocator, "_is_variadic", .{ .bool = is_variadic });

    const has_default = !is_variadic and i >= func.required_params;
    try obj.set(ctx.allocator, "_has_default", .{ .bool = has_default });
    if (has_default and i < func.defaults.len) {
        const raw = func.defaults[i];
        try obj.set(ctx.allocator, "_default_value", try ctx.vm.resolveDefault(raw));
        if (try decodeConstSentinel(ctx, raw)) |const_name| {
            try obj.set(ctx.allocator, "_default_const_name", .{ .string = Value.String.borrowed(const_name) });
        }
    }

    const by_ref = if (i < func.ref_params.len) func.ref_params[i] else false;
    try obj.set(ctx.allocator, "_by_reference", .{ .bool = by_ref });

    if (std.mem.indexOf(u8, type_key, "::")) |sep| {
        const decl_class = try ctx.allocator.dupe(u8, type_key[0..sep]);
        try ctx.strings.append(ctx.allocator, decl_class);
        try obj.set(ctx.allocator, "_declaring_class", .{ .string = Value.String.borrowed(decl_class) });
        const meth_name = try ctx.allocator.dupe(u8, type_key[sep + 2 ..]);
        try ctx.strings.append(ctx.allocator, meth_name);
        try obj.set(ctx.allocator, "_method_name", .{ .string = Value.String.borrowed(meth_name) });
    }
}

fn rpConstructParam(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) return throwReflection(ctx, "ReflectionParameter::__construct expects function and parameter");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);

    // accept "func_name" | ["Class", "method"] | [$obj, "method"] | Closure-ish
    var key_buf: [256]u8 = undefined;
    var lookup_key: []const u8 = "";
    switch (args[0]) {
        .string => |s| {
            lookup_key = s.bytes();
        },
        .array => |arr| {
            if (arr.entries.items.len < 2) return throwReflection(ctx, "ReflectionParameter callable must have [class, method]");
            const cls_val = arr.entries.items[0].value;
            const meth_val = arr.entries.items[1].value;
            if (meth_val != .string) return throwReflection(ctx, "ReflectionParameter method name must be string");
            const cls_name: []const u8 = switch (cls_val) {
                .string => cls_val.string.bytes(),
                .object => cls_val.object.class_name,
                else => return throwReflection(ctx, "ReflectionParameter class must be a string or object"),
            };
            lookup_key = std.fmt.bufPrint(&key_buf, "{s}::{s}", .{ cls_name, meth_val.string.bytes() }) catch return throwReflection(ctx, "ReflectionParameter name too long");
        },
        else => return throwReflection(ctx, "ReflectionParameter expects a function name or [class, method]"),
    }

    const func = ctx.vm.functions.get(lookup_key) orelse return throwReflection(ctx, "ReflectionParameter could not find function");

    var idx: ?usize = null;
    switch (args[1]) {
        .int => |n| if (n >= 0 and @as(usize, @intCast(n)) < func.params.len) {
            idx = @intCast(n);
        },
        .string => |want| {
            for (func.params, 0..) |p, i| {
                const clean = if (p.len > 0 and p[0] == '$') p[1..] else p;
                if (std.mem.eql(u8, clean, want.bytes())) {
                    idx = i;
                    break;
                }
            }
        },
        else => {},
    }
    if (idx == null) return throwReflection(ctx, "ReflectionParameter could not find parameter");

    try populateRpFields(ctx, this, func, lookup_key, idx.?);
    return NativeResult.scalar(.null);
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
    const type_info = vm_mod.getTypeInfo(effective_key) orelse vm_mod.getTypeInfo(type_key);

    for (func.params, 0..) |param_name, i| {
        const obj = try ctx.createObject("ReflectionParameter");

        const clean_name = if (param_name.len > 0 and param_name[0] == '$') param_name[1..] else param_name;
        try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(clean_name) });
        try obj.set(ctx.allocator, "_position", .{ .int = @intCast(i) });

        if (type_info) |ti| {
            if (i < ti.param_types.len and ti.param_types[i].len > 0) {
                const raw_type = ti.param_types[i];
                if (raw_type[0] == '?') {
                    try obj.set(ctx.allocator, "_type_name", .{ .string = Value.String.borrowed(raw_type[1..]) });
                    try obj.set(ctx.allocator, "_nullable", .{ .bool = true });
                } else {
                    try obj.set(ctx.allocator, "_type_name", .{ .string = Value.String.borrowed(raw_type) });
                    try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
                }
            } else {
                try obj.set(ctx.allocator, "_type_name", .{ .string = Value.String.borrowed("") });
                try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
            }
        } else {
            try obj.set(ctx.allocator, "_type_name", .{ .string = Value.String.borrowed("") });
            try obj.set(ctx.allocator, "_nullable", .{ .bool = false });
        }

        const is_variadic = func.is_variadic and i == func.arity - 1;
        try obj.set(ctx.allocator, "_is_variadic", .{ .bool = is_variadic });

        // default values - defaults array has one entry per param, non-default params have .null
        // variadic params never have a default (they collect remaining args)
        const has_default = !is_variadic and i >= func.required_params;
        try obj.set(ctx.allocator, "_has_default", .{ .bool = has_default });
        if (has_default and i < func.defaults.len) {
            const raw = func.defaults[i];
            try obj.set(ctx.allocator, "_default_value", try ctx.vm.resolveDefault(raw));
            if (try decodeConstSentinel(ctx, raw)) |const_name| {
                try obj.set(ctx.allocator, "_default_const_name", .{ .string = Value.String.borrowed(const_name) });
            }
        }

        const by_ref = if (i < func.ref_params.len) func.ref_params[i] else false;
        try obj.set(ctx.allocator, "_by_reference", .{ .bool = by_ref });

        // declaring class and method name (or bare function name for free fns)
        if (std.mem.indexOf(u8, type_key, "::")) |sep| {
            const decl_class = try ctx.allocator.dupe(u8, type_key[0..sep]);
            try ctx.strings.append(ctx.allocator, decl_class);
            try obj.set(ctx.allocator, "_declaring_class", .{ .string = Value.String.borrowed(decl_class) });
            const meth_name = try ctx.allocator.dupe(u8, type_key[sep + 2 ..]);
            try ctx.strings.append(ctx.allocator, meth_name);
            try obj.set(ctx.allocator, "_method_name", .{ .string = Value.String.borrowed(meth_name) });
            try obj.set(ctx.allocator, "_function", .{ .string = Value.String.borrowed(meth_name) });
        } else {
            const fname = try ctx.allocator.dupe(u8, type_key);
            try ctx.strings.append(ctx.allocator, fname);
            try obj.set(ctx.allocator, "_function", .{ .string = Value.String.borrowed(fname) });
        }

        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return .{ .array = arr };
}

fn closureBind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.null);
    const closure = args[0];
    if (closure != .string or !std.mem.startsWith(u8, closure.string.bytes(), "__closure_")) return NativeResult.scalar(.null);
    const new_this = if (args.len >= 2) args[1] else Value.null;
    const scope = resolveScope(args);
    return NativeResult.transfer(try ctx.vm.cloneClosureWithThis(closure.string.bytes(), new_this, scope));
}

fn resolveScope(args: []const Value) VM.ClosureScope {
    if (args.len >= 3) {
        const scope_arg = args[2];
        if (scope_arg == .null) return .clear;
        if (scope_arg == .string) {
            if (std.mem.eql(u8, scope_arg.string.bytes(), "static")) return .preserve;
            return .{ .set = scope_arg.string.bytes() };
        }
        if (scope_arg == .object) return .{ .set = scope_arg.object.class_name };
        return .clear;
    }
    return .preserve;
}

fn wrapCallableClosure(ctx: *NativeContext, callable: Value) RuntimeError!NativeResult {
    const obj = try ctx.createObject("Closure");
    try obj.set(ctx.allocator, "__callable", callable);
    return NativeResult.borrowed(.{ .object = obj });
}

fn closureFromCallable(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.null);
    const callable = args[0];
    if (callable == .object and std.mem.eql(u8, callable.object.class_name, "Closure")) return NativeResult.share(callable);
    // if already a closure, return as-is
    if (callable == .string and std.mem.startsWith(u8, callable.string.bytes(), "__closure_")) return NativeResult.share(callable);
    if (callable == .string) {
        const raw = callable.string.bytes();
        const name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
        if (ctx.vm.functions.contains(name) or ctx.vm.native_fns.contains(name)) {
            // when input had a leading backslash, return the normalized form
            // so subsequent invocations find the function
            if (name.len != raw.len) {
                const owned = try ctx.allocator.dupe(u8, name);
                try ctx.strings.append(ctx.allocator, owned);
                return wrapCallableClosure(ctx, .{ .string = Value.String.borrowed(owned) });
            }
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
                    const full = std.fmt.allocPrint(ctx.allocator, "{s}::{s}", .{ entries[0].value.string.bytes(), method }) catch return NativeResult.scalar(.null);
                    try ctx.strings.append(ctx.allocator, full);
                    return wrapCallableClosure(ctx, .{ .string = Value.String.borrowed(full) });
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

fn methodLookupName(obj: *PhpObject) ?[]const u8 {
    const internal = obj.get("_hook_method");
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
    const declaring = this.get("_declaring_class");
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
    try ctx.strings.append(ctx.allocator, display);
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(display) });
    try obj.set(ctx.allocator, "_hook_method", .{ .string = Value.String.borrowed(hook.info.name) });
    try obj.set(ctx.allocator, "_hook_property", this.get("name"));
    const prop = findPropertyDef(ctx.vm, hook.declaring, this.get("name").string.bytes());
    const return_type = if (std.mem.eql(u8, kind, "set")) "void" else if (prop) |p| p.prop.type_str else "";
    try obj.set(ctx.allocator, "_hook_return_type", .{ .string = Value.String.borrowed(return_type) });
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

fn rrefFromArrayElement(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn rrefGetId(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn rpConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 2) {
        return throwReflection(
            ctx,
            "ReflectionProperty::__construct() expects class and property name",
        );
    }

    const this = getThis(ctx) orelse return NativeResult.scalar(.null);

    const raw_class = if (args[0] == .string)
        args[0].string.bytes()
    else if (args[0] == .object)
        args[0].object.class_name
    else
        return throwReflection(
            ctx,
            "ReflectionProperty::__construct() expects a class name",
        );

    const class_name = if (raw_class.len > 0 and raw_class[0] == '\\')
        raw_class[1..]
    else
        raw_class;

    const prop_name = if (args[1] == .string)
        args[1].string.bytes()
    else
        return throwReflection(
            ctx,
            "ReflectionProperty::__construct() expects a property name",
        );

    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(prop_name) });
    try this.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(class_name) });

    if (findPropertyDef(ctx.vm, class_name, prop_name)) |result| {
        try this.set(
            ctx.allocator,
            "_visibility",
            .{ .int = @intFromEnum(result.prop.visibility) },
        );

        const effective_has_default =
            result.prop.has_default and !result.prop.is_promoted;

        try this.set(
            ctx.allocator,
            "_has_default",
            .{ .bool = effective_has_default },
        );

        try this.set(
            ctx.allocator,
            "_default_value",
            if (effective_has_default) result.prop.default else .null,
        );

        try this.set(
            ctx.allocator,
            "_declaring_class",
            .{ .string = Value.String.borrowed(result.declaring_class) },
        );

        try this.set(
            ctx.allocator,
            "_set_visibility",
            .{ .int = @intFromEnum(result.prop.set_visibility) },
        );

        try this.set(
            ctx.allocator,
            "_has_set_visibility",
            .{ .bool = result.prop.has_set_visibility },
        );

        try this.set(
            ctx.allocator,
            "_is_readonly",
            .{ .bool = result.prop.is_readonly },
        );

        try this.set(
            ctx.allocator,
            "_is_final",
            .{ .bool = result.prop.is_final },
        );

        try this.set(
            ctx.allocator,
            "_is_static",
            .{ .bool = result.is_static },
        );
    } else {
        const msg = try std.fmt.allocPrint(
            ctx.allocator,
            "Property {s}::${s} does not exist",
            .{ class_name, prop_name },
        );

        try ctx.vm.strings.append(ctx.allocator, msg);

        return throwReflection(ctx, msg);
    }

    return NativeResult.scalar(.null);
}

fn rpGetValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (args.len > 0 and args[0] == .object) {
        const dc = this.get("_declaring_class");
        if (dc == .string and !ctx.vm.isInstanceOf(args[0].object.class_name, dc.string.bytes()))
            return throwReflection(ctx, "Given object is not an instance of the class this property was declared in");
        try ctx.vm.triggerLazyProperty(args[0].object, prop_name, if (dc == .string) dc.string.bytes() else null);
        return NativeResult.share(args[0].object.getForScope(prop_name, if (dc == .string) dc.string.bytes() else null));
    }
    return NativeResult.scalar(.null);
}

fn rpSetValue(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return rpWrite(ctx, args, false);
}
fn rpSetWithoutLazy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return rpWrite(ctx, args, true);
}
fn rpSkipLazy(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len == 0 or args[0] != .object) return NativeResult.scalar(.null);
    const name = this.get("name");
    const dc = this.get("_declaring_class");
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
    const dc = this.get("_declaring_class");
    return NativeResult.scalar(.{ .bool = name == .string and args[0].object.isLazySlot(name.string.bytes(), if (dc == .string) dc.string.bytes() else null) });
}
fn rpWrite(ctx: *NativeContext, args: []const Value, skip: bool) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    if (args.len >= 2 and args[0] == .object) {
        const target = args[0].object;
        const dc = this.get("_declaring_class");
        const scope = if (dc == .string) dc.string.bytes() else target.class_name;
        if (!skip) try ctx.vm.triggerLazyProperty(target, prop_name, scope);
        const vr = ctx.vm.findPropertyVisibility(scope, prop_name);
        if (vr.is_readonly and target.getForScope(prop_name, scope) != .null) {
            const msg = try std.fmt.allocPrint(ctx.allocator, "Cannot modify readonly property {s}::${s}", .{ vr.defining_class, prop_name });
            try ctx.vm.strings.append(ctx.allocator, msg);
            _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
            return error.RuntimeError;
        }
        var value = args[1];
        if (try ctx.vm.checkPropertyType(&value, vr.type_str, scope, prop_name)) return error.RuntimeError;
        try target.setForScope(ctx.allocator, prop_name, value, scope);
        if (skip) _ = try rpSkipLazy(ctx, args);
    }
    return NativeResult.scalar(.null);
}

fn rpropGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn rpropGetType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const dc_v = this.get("_declaring_class");
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
    try ctx.strings.append(ctx.allocator, dup);
    try obj.set(ctx.allocator, "type_name", .{ .string = Value.String.borrowed(dup) });
    try obj.set(ctx.allocator, "nullable", .{ .bool = allows_null or std.mem.eql(u8, name, "mixed") or std.mem.eql(u8, name, "null") });
    try obj.set(ctx.allocator, "is_builtin", .{ .bool = isBuiltinTypeName(name) });
    return .{ .object = obj };
}

fn isBuiltinTypeName(name: []const u8) bool {
    const builtins = [_][]const u8{ "int", "float", "string", "bool", "array", "object", "callable", "iterable", "void", "mixed", "never", "null", "false", "true", "self", "static", "parent" };
    for (builtins) |b| if (std.mem.eql(u8, b, name)) return true;
    return false;
}

fn rpropIsPublic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = true });
    const vis = this.get("_visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 0 });
}

fn rpropIsProtected(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("_visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 1 });
}

fn rpropIsPrivate(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("_visibility");
    return NativeResult.scalar(.{ .bool = vis == .int and vis.int == 2 });
}

fn rpropIsPrivateSet(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("_visibility");
    const set_vis = this.get("_set_visibility");
    const vis_val = if (vis == .int) vis.int else 0;
    const set_vis_val = if (set_vis == .int) set_vis.int else vis_val;
    return NativeResult.scalar(.{ .bool = set_vis_val == 2 and vis_val != 2 });
}

fn rpropIsProtectedSet(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const vis = this.get("_visibility");
    const set_vis = this.get("_set_visibility");
    const has_set_vis = this.get("_has_set_visibility");
    const ro = this.get("_is_readonly");
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

    const final_v = this.get("_is_final");
    const is_explicit_final = final_v == .bool and final_v.bool;
    if (is_explicit_final) return NativeResult.scalar(.{ .bool = true });

    const vis = this.get("_visibility");
    const set_vis = this.get("_set_visibility");
    const has_set_vis = this.get("_has_set_visibility");
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
    const has_default = this.get("_has_default");
    if (has_default != .bool or !has_default.bool) return throwReflection(ctx, "Property does not have a default value");
    return NativeResult.share(this.get("_default_value"));
}

fn rpropHasDefaultValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const has_default = this.get("_has_default");
    return NativeResult.scalar(.{ .bool = has_default == .bool and has_default.bool });
}

fn rpropIsInitialized(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    if (args.len > 0 and args[0] == .object) {
        const dc = this.get("_declaring_class");
        const scope = if (dc == .string) dc.string.bytes() else args[0].object.class_name;
        try ctx.vm.triggerLazyProperty(args[0].object, prop_name, scope);
        const vr = ctx.vm.findPropertyVisibility(scope, prop_name);
        return NativeResult.scalar(.{ .bool = !args[0].object.isUnset(prop_name) and (args[0].object.getForScope(prop_name, scope) != .null or vr.type_str.len == 0 or (findPropertyDef(ctx.vm, scope, prop_name) orelse return NativeResult.scalar(.{ .bool = false })).prop.has_default) });
    }
    return NativeResult.scalar(.{ .bool = true });
}

fn rpropGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.null);

    const obj = try ctx.createObject("ReflectionClass");
    try obj.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(declaring) });
    try obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(declaring) });
    return NativeResult.borrowed(.{ .object = obj });
}

fn rpropIsDefault(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn rpropIsReadOnly(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = this.get("_is_readonly");
    return NativeResult.scalar(.{ .bool = v == .bool and v.bool });
}

fn rpropIsStatic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = this.get("_is_static");
    return NativeResult.scalar(.{ .bool = v == .bool and v.bool });
}

fn rpropIsPromoted(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // a property is promoted iff it appears as a constructor parameter that
    // had a visibility modifier (zphp tracks promotion on the constructor's
    // params; detect it by matching the property name against the ctor's
    // param list)
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const class_name = if (this.get("_declaring_class") == .string)
        this.get("_declaring_class").string.bytes()
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
    const vis = this.get("_visibility");
    const vis_val = if (vis == .int) vis.int else 0;

    var mods: i64 = switch (vis_val) {
        1 => 2, // IS_PROTECTED
        2 => 4, // IS_PRIVATE
        else => 1, // IS_PUBLIC
    };

    const st = this.get("_is_static");
    if (st == .bool and st.bool) mods |= 16;

    const ro = this.get("_is_readonly");
    const is_ro = ro == .bool and ro.bool;
    if (is_ro) mods |= 128;

    const set_vis = this.get("_set_visibility");
    const has_set_vis = this.get("_has_set_visibility");
    const set_vis_val = if (set_vis == .int) set_vis.int else vis_val;
    const has_explicit_set = has_set_vis == .bool and has_set_vis.bool;

    const final_v = this.get("_is_final");
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

    return NativeResult.scalar(.{ .int = mods });
}

fn rpropGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const prop_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const attrs = cls.property_attributes.get(prop_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 8, flags);
}

fn rpropGetDocComment(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const dc_v = this.get("_declaring_class");
    if (dc_v != .string) return NativeResult.scalar(.{ .bool = false });
    const prop_name_v = this.get("name");
    if (prop_name_v != .string) return NativeResult.scalar(.{ .bool = false });
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
    const dc = this.get("_declaring_class");
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
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const guard_count = ctx.vm.prop_hook_guard.items.len;
    defer ctx.vm.prop_hook_guard.shrinkRetainingCapacity(guard_count);
    if (this.get("_hook_property") == .string and args.len > 0 and args[0] == .object) {
        try ctx.vm.prop_hook_guard.append(ctx.allocator, .{ .obj_ptr = @intFromPtr(args[0].object), .prop_name = this.get("_hook_property").string.bytes() });
    }
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    if (args.len > 0 and args[0] == .object) {
        return NativeResult.share(ctx.callMethod(args[0].object, method_name, args[1..]) catch .null);
    }
    // static call: target is null/missing, dispatch by ClassName::methodName
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.null);
    var buf: [256]u8 = undefined;
    const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return NativeResult.scalar(.null);
    const rest = if (args.len >= 1) args[1..] else args[0..];
    return NativeResult.share(ctx.vm.callByName(full, rest) catch .null);
}

fn rmInvokeArgs(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const guard_count = ctx.vm.prop_hook_guard.items.len;
    defer ctx.vm.prop_hook_guard.shrinkRetainingCapacity(guard_count);
    if (this.get("_hook_property") == .string and args.len > 0 and args[0] == .object) {
        try ctx.vm.prop_hook_guard.append(ctx.allocator, .{ .obj_ptr = @intFromPtr(args[0].object), .prop_name = this.get("_hook_property").string.bytes() });
    }
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const target = args[0];

    var call_args: [16]Value = undefined;
    var count: usize = 0;
    if (args.len >= 2 and args[1] == .array) {
        const arg_arr = args[1].array;
        count = @min(arg_arr.entries.items.len, 16);
        for (0..count) |i| call_args[i] = arg_arr.entries.items[i].value;
    }

    if (target == .object) {
        return NativeResult.share(ctx.callMethod(target.object, method_name, call_args[0..count]) catch .null);
    }
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.null);
    var buf: [256]u8 = undefined;
    const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return NativeResult.scalar(.null);
    return NativeResult.share(ctx.vm.callByName(full, call_args[0..count]) catch .null);
}

fn rmGetClosure(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);

    const arr = try ctx.createArray();
    try arr.append(ctx.allocator, args[0]);
    try arr.append(ctx.allocator, .{ .string = Value.String.borrowed(method_name) });
    return NativeResult.borrowed(.{ .array = arr });
}

fn rmIsAbstract(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .bool = false });
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });

    if (ctx.vm.interfaces.contains(declaring)) return NativeResult.scalar(.{ .bool = true });

    if (ctx.vm.classes.get(declaring)) |cls| {
        if (cls.methods.get(method_name)) |m| {
            if (m.is_abstract) return NativeResult.scalar(.{ .bool = true });
        }
    }

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.functions.get(key) == null and ctx.vm.native_fns.get(key) == null) return NativeResult.scalar(.{ .bool = true });
    return NativeResult.scalar(.{ .bool = false });
}

fn rmIsFinal(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .bool = false });
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.{ .bool = false });
    const m = cls.methods.get(method_name) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = m.is_final });
}

fn rmFullName(ctx: *NativeContext) ?[]const u8 {
    const this = getThis(ctx) orelse return null;
    const method_name = methodLookupName(this) orelse return null;
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return null;
    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return null;
    const owned = ctx.allocator.dupe(u8, key) catch return null;
    ctx.vm.strings.append(ctx.allocator, owned) catch {};
    return owned;
}

fn rmIsVariadic(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const key = rmFullName(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(key) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.is_variadic });
}

fn rmIsGenerator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const key = rmFullName(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const func = ctx.vm.functions.get(key) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = func.is_generator });
}

fn rmGetModifiers(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const method_name = methodLookupName(this) orelse return NativeResult.scalar(.{ .int = 0 });
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.scalar(.{ .int = 0 });
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.scalar(.{ .int = 0 });
    const info = cls.methods.get(method_name) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = if (this.get("_hook_method") == .string) (methodModifiers(info) & ~@as(i64, 7)) | 1 else methodModifiers(info) });
}

fn reflectionGetModifierNames(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .int) return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const m = args[0].int;
    const arr = try ctx.createArray();
    if ((m & 16) != 0) try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("static") });
    if ((m & 64) != 0) try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("abstract") });
    if ((m & 32) != 0) try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("final") });
    if ((m & 4) != 0) try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("private") });
    if ((m & 2) != 0) try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("protected") });
    if ((m & 1) != 0) try arr.append(ctx.allocator, .{ .string = Value.String.borrowed("public") });
    return NativeResult.borrowed(.{ .array = arr });
}

fn rmGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const method_name = methodLookupName(this) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string.bytes() else return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const cls = ctx.vm.classes.get(declaring) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const attrs = cls.method_attributes.get(method_name) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string.bytes() else null;
    const flags: i64 = if (args.len >= 2 and args[1] == .int) args[1].int else 0;
    return buildAttributeArrayWithFlags(ctx, attrs, filter, 4, flags);
}

fn rpIsPromoted(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    // promoted iff declaring method is __construct AND the class has a
    // matching property that is itself flagged as promoted. previously we
    // returned true whenever any same-named property existed, which mis-
    // classified plain '?string $name = null' params as promoted whenever
    // the class happened to declare a separate '$name' property
    const method_v = this.get("_method_name");
    if (method_v != .string or !std.mem.eql(u8, method_v.string.bytes(), "__construct")) return NativeResult.scalar(.{ .bool = false });
    const class_v = this.get("_declaring_class");
    if (class_v != .string) return NativeResult.scalar(.{ .bool = false });
    const name_v = this.get("name");
    if (name_v != .string) return NativeResult.scalar(.{ .bool = false });
    const cls = ctx.vm.classes.getPtr(class_v.string.bytes()) orelse return NativeResult.scalar(.{ .bool = false });
    for (cls.properties.items) |prop| {
        if (std.mem.eql(u8, prop.name, name_v.string.bytes())) return NativeResult.scalar(.{ .bool = prop.is_promoted });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn rpGetClass(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const type_val = this.get("_type_name");
    if (type_val != .string or type_val.string.bytes().len == 0) return NativeResult.scalar(.null);
    if (isBuiltinType(type_val.string.bytes())) return NativeResult.scalar(.null);

    if (ctx.vm.classes.contains(type_val.string.bytes()) or ctx.vm.interfaces.contains(type_val.string.bytes())) {
        const obj = try ctx.createObject("ReflectionClass");
        try obj.set(ctx.allocator, "name", type_val);
        try obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(type_val.string.bytes()) });
        return NativeResult.borrowed(.{ .object = obj });
    }
    return NativeResult.scalar(.null);
}

fn attributeConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const flags = if (args.len > 0 and args[0] == .int) args[0] else Value{ .int = 127 };
    try this.set(ctx.allocator, "flags", flags);
    return NativeResult.scalar(.null);
}

fn raGetName(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(this.get("name"));
}

fn raGetArguments(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.borrowed(.{ .array = try ctx.createArray() });
    const args = this.get("_arguments");
    if (args == .array) return NativeResult.share(args);
    return NativeResult.borrowed(.{ .array = try ctx.createArray() });
}

fn targetName(t: i64) []const u8 {
    return switch (t) {
        1 => "class",
        2 => "function",
        4 => "method",
        8 => "property",
        16 => "class constant",
        32 => "parameter",
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

fn getAttributeFlags(vm: *VM, class_name: []const u8) i64 {
    const cls = vm.classes.get(class_name) orelse return 127;
    for (cls.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.name, "Attribute")) {
            if (attr.args.len > 0 and attr.args[0] == .int) return attr.args[0].int;
            return 127; // TARGET_ALL
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
        try ctx.strings.append(ctx.allocator, msg);
        _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
        return error.RuntimeError;
    }

    if (!isAttributeClass(ctx.vm, attr_name)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Attempting to use non-attribute class \"{s}\" as attribute", .{attr_name}) catch return error.OutOfMemory;
        try ctx.strings.append(ctx.allocator, msg);
        _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
        return error.RuntimeError;
    }

    const target_val = this.get("_target");
    if (target_val == .int) {
        const target = target_val.int;
        const flags = getAttributeFlags(ctx.vm, attr_name);
        if (flags != 127 and (flags & target) == 0) {
            const used = targetName(target);
            var allowed_buf: std.ArrayListUnmanaged(u8) = .{};
            defer allowed_buf.deinit(ctx.allocator);
            const bits = [_]i64{ 1, 2, 4, 8, 16, 32 };
            for (bits) |b| {
                if ((flags & b) != 0) {
                    if (allowed_buf.items.len > 0) try allowed_buf.appendSlice(ctx.allocator, ", ");
                    try allowed_buf.appendSlice(ctx.allocator, targetName(b));
                }
            }
            const msg = std.fmt.allocPrint(ctx.allocator, "Attribute \"{s}\" cannot target {s} (allowed targets: {s})", .{ attr_name, used, allowed_buf.items }) catch return error.OutOfMemory;
            try ctx.strings.append(ctx.allocator, msg);
            _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
            return error.RuntimeError;
        }
    }

    const is_repeated_val = this.get("_is_repeated");
    if (is_repeated_val == .bool and is_repeated_val.bool) {
        const flags = getAttributeFlags(ctx.vm, attr_name);
        if ((flags & 128) == 0) {
            const msg = std.fmt.allocPrint(ctx.allocator, "Attribute \"{s}\" must not be repeated", .{attr_name}) catch return error.OutOfMemory;
            try ctx.strings.append(ctx.allocator, msg);
            _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
            return error.RuntimeError;
        }
    }

    const obj = try ctx.createObject(attr_name);
    const args_val = this.get("_arguments");
    // always call __construct even with zero attribute args - constructors
    // commonly have all-optional params plus initialization side effects
    // (e.g. Symfony's Constraint::__construct does `unset($this->groups)`
    // to set up lazy default-group handling)
    if (args_val != .array or args_val.array.entries.items.len == 0) {
        _ = ctx.callMethod(obj, "__construct", &.{}) catch {};
        return NativeResult.borrowed(.{ .object = obj });
    }
    if (args_val == .array) {
        const arr = args_val.array;
        var has_named = false;
        for (arr.entries.items) |entry| {
            if (entry.key == .string) {
                has_named = true;
                break;
            }
        }

        if (has_named) {
            var buf: [256]u8 = undefined;
            const ctor_key = std.fmt.bufPrint(&buf, "{s}::__construct", .{attr_name}) catch "";
            if (ctx.vm.functions.get(ctor_key)) |func| {
                var resolved: [16]Value = .{.null} ** 16;
                var pos: usize = 0;
                for (arr.entries.items) |entry| {
                    if (entry.key == .string) {
                        for (func.params, 0..) |p, pi| {
                            const pn = if (p.len > 0 and p[0] == '$') p[1..] else p;
                            if (std.mem.eql(u8, pn, entry.key.string.bytes())) {
                                resolved[pi] = entry.value;
                                if (pi >= pos) pos = pi + 1;
                                break;
                            }
                        }
                    } else {
                        resolved[pos] = entry.value;
                        pos += 1;
                    }
                }
                const count = @max(pos, func.required_params);
                for (0..count) |i| {
                    if (resolved[i] == .null and i < func.defaults.len) {
                        resolved[i] = try ctx.vm.resolveDefault(func.defaults[i]);
                    }
                }
                if (count > 0) _ = try ctx.callMethod(obj, "__construct", resolved[0..count]);
            } else {
                var call_args: [16]Value = undefined;
                const count = @min(arr.entries.items.len, 16);
                for (0..count) |i| call_args[i] = arr.entries.items[i].value;
                _ = try ctx.callMethod(obj, "__construct", call_args[0..count]);
            }
        } else {
            var call_args: [16]Value = undefined;
            const count = @min(arr.entries.items.len, 16);
            for (0..count) |i| call_args[i] = arr.entries.items[i].value;
            if (count > 0) _ = try ctx.callMethod(obj, "__construct", call_args[0..count]);
        }
    }
    return NativeResult.borrowed(.{ .object = obj });
}

fn raGetTarget(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const target = this.get("_target");
    return if (target == .int) NativeResult.share(target) else NativeResult.scalar(.{ .int = 0 });
}

fn raIsRepeated(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const repeated = this.get("_is_repeated");
    return if (repeated == .bool) NativeResult.share(repeated) else NativeResult.scalar(.{ .bool = false });
}

fn reConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return throwReflection(ctx, "ReflectionEnum::__construct() expects an enum name");
    const raw = if (args[0] == .string)
        args[0].string.bytes()
    else if (args[0] == .object)
        args[0].object.class_name
    else
        return throwReflection(ctx, "ReflectionEnum::__construct() expects an enum name or object");
    const class_name = if (raw.len > 0 and raw[0] == '\\') raw[1..] else raw;
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);

    const cls = ctx.vm.classes.get(class_name) orelse {
        const msg = std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" does not exist", .{class_name}) catch return throwReflection(ctx, "Class does not exist");
        try ctx.strings.append(ctx.allocator, msg);
        return throwReflection(ctx, msg);
    };
    if (!cls.is_enum) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Class \"{s}\" is not an enum", .{class_name}) catch return throwReflection(ctx, "Not an enum");
        try ctx.strings.append(ctx.allocator, msg);
        return throwReflection(ctx, msg);
    }

    const stable_name = try ctx.createString(class_name);
    try this.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(stable_name) });
    try this.set(ctx.allocator, "_is_interface", .{ .bool = false });
    try this.set(ctx.allocator, "_is_trait", .{ .bool = false });
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
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionEnum::getCase() expects a name");
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.null);
    if (!cls.constant_names.contains(args[0].string.bytes())) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Case {s}::{s} does not exist", .{ class_name, args[0].string.bytes() }) catch return throwReflection(ctx, "Case not found");
        try ctx.strings.append(ctx.allocator, msg);
        return throwReflection(ctx, msg);
    }
    const obj = try buildEnumCase(ctx, class_name, args[0].string.bytes(), cls.backed_type != .none);
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
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 2) return NativeResult.scalar(.null);
    const class_name: []const u8 = switch (args[0]) {
        .string => |s| s.bytes(),
        .object => |o| o.class_name,
        else => return NativeResult.scalar(.null),
    };
    if (args[1] != .string) return NativeResult.scalar(.null);
    try this.set(ctx.allocator, "class", .{ .string = Value.String.borrowed(class_name) });
    try this.set(ctx.allocator, "name", .{ .string = args[1].string });
    return NativeResult.scalar(.null);
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
    return NativeResult.share(cls.static_props.get(case_name) orelse .null);
}

fn rebcGetBackingValue(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const class_name = if (this.get("class") == .string) this.get("class").string.bytes() else return NativeResult.scalar(.null);
    const case_name = if (this.get("name") == .string) this.get("name").string.bytes() else return NativeResult.scalar(.null);
    const cls = ctx.vm.classes.get(class_name) orelse return NativeResult.scalar(.null);
    const case_obj_v = cls.static_props.get(case_name) orelse return NativeResult.scalar(.null);
    if (case_obj_v != .object) return NativeResult.scalar(.null);
    return NativeResult.share(case_obj_v.object.get("value"));
}

fn rgConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .generator) return throwReflection(ctx, "ReflectionGenerator::__construct expects a Generator");
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__gen", .{ .int = @intCast(@intFromPtr(args[0].generator)) });
    return NativeResult.scalar(.null);
}

fn getGenPtr(obj: *PhpObject) ?*@import("../runtime/value.zig").Generator {
    const v = obj.get("__gen");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn rgGetExecutingLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = getGenPtr(obj) orelse return NativeResult.scalar(.null);
    const chunk = &gen.func.chunk;
    const ip = if (gen.ip > 0) gen.ip - 1 else 0;
    if (chunk.getSourceLocation(ip, ctx.vm.source)) |loc| {
        return NativeResult.scalar(.{ .int = @intCast(loc.line) });
    }
    return NativeResult.scalar(.{ .int = 0 });
}

fn rgGetExecutingFile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = getGenPtr(obj) orelse return NativeResult.scalar(.null);
    _ = gen;
    // zphp stores a single source per VM; surface that as the executing file
    return try NativeResult.copyString(ctx.allocator, ctx.vm.file_path);
}

fn rgGetFunction(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = getGenPtr(obj) orelse return NativeResult.scalar(.null);
    const rf = try ctx.createObject("ReflectionFunction");
    try rf.set(ctx.allocator, "name", .{ .string = Value.String.borrowed(try ctx.createString(gen.func.name)) });
    return NativeResult.borrowed(.{ .object = rf });
}

fn rgGetThis(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = getGenPtr(obj) orelse return NativeResult.scalar(.null);
    if (gen.vars.get("$this")) |this_v| return NativeResult.share(this_v);
    return NativeResult.scalar(.null);
}

fn rgGetExecutingGenerator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    var gen = getGenPtr(obj) orelse return NativeResult.scalar(.null);
    // walk yield-from delegates to the innermost actually-executing generator
    while (gen.delegate) |del| switch (del) {
        .gen => |inner| gen = inner,
        else => break,
    };
    return NativeResult.borrowed(.{ .generator = gen });
}

fn rgGetTrace(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = getGenPtr(obj) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    const frame = try ctx.createArray();
    if (gen.func.chunk.getSourceLocation(if (gen.ip > 0) gen.ip - 1 else 0, ctx.vm.source)) |loc| {
        try frame.set(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString("line")) }, .{ .int = @intCast(loc.line) });
    }
    try frame.set(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString("file")) }, .{ .string = Value.String.borrowed(try ctx.createString(ctx.vm.file_path)) });
    try frame.set(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString("function")) }, .{ .string = Value.String.borrowed(try ctx.createString(gen.func.name)) });
    try arr.append(ctx.allocator, .{ .array = frame });
    return NativeResult.borrowed(.{ .array = arr });
}

fn rfibConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1 or args[0] != .fiber) return throwReflection(ctx, "ReflectionFiber::__construct expects a Fiber");
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__fib", .{ .int = @intCast(@intFromPtr(args[0].fiber)) });
    return NativeResult.scalar(.null);
}

fn getFibPtr(obj: *PhpObject) ?*@import("../runtime/value.zig").Fiber {
    const v = obj.get("__fib");
    if (v != .int or v.int == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(v.int)));
}

fn rfibGetExecutingLine(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fib = getFibPtr(obj) orelse return NativeResult.scalar(.null);
    if (fib.saved_frames.items.len == 0) return NativeResult.scalar(.{ .int = 0 });
    const top = &fib.saved_frames.items[fib.saved_frames.items.len - 1];
    const ip = if (top.ip > 0) top.ip - 1 else 0;
    if (top.chunk.getSourceLocation(ip, ctx.vm.source)) |loc| {
        return NativeResult.scalar(.{ .int = @intCast(loc.line) });
    }
    return NativeResult.scalar(.{ .int = 0 });
}

fn rfibGetExecutingFile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    _ = getFibPtr(obj) orelse return NativeResult.scalar(.null);
    return try NativeResult.copyString(ctx.allocator, ctx.vm.file_path);
}

fn rfibGetCallable(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fib = getFibPtr(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(fib.callable);
}

fn rfibGetFiber(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fib = getFibPtr(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .fiber = fib });
}

fn rfibGetTrace(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const fib = getFibPtr(obj) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    var i: usize = fib.saved_frames.items.len;
    while (i > 0) {
        i -= 1;
        const sf = &fib.saved_frames.items[i];
        const frame = try ctx.createArray();
        const ip = if (sf.ip > 0) sf.ip - 1 else 0;
        if (sf.chunk.getSourceLocation(ip, ctx.vm.source)) |loc| {
            try frame.set(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString("line")) }, .{ .int = @intCast(loc.line) });
        }
        try frame.set(ctx.allocator, .{ .string = Value.String.borrowed(try ctx.createString("file")) }, .{ .string = Value.String.borrowed(try ctx.createString(ctx.vm.file_path)) });
        try arr.append(ctx.allocator, .{ .array = frame });
    }
    return NativeResult.borrowed(.{ .array = arr });
}
