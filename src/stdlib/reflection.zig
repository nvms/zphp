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

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    // Attribute class with target constants
    var attr_def = ClassDef{ .name = "Attribute" };
    try attr_def.static_props.put(a, "TARGET_CLASS", .{ .int = 1 });
    try attr_def.static_props.put(a, "TARGET_FUNCTION", .{ .int = 2 });
    try attr_def.static_props.put(a, "TARGET_METHOD", .{ .int = 4 });
    try attr_def.static_props.put(a, "TARGET_PROPERTY", .{ .int = 8 });
    try attr_def.static_props.put(a, "TARGET_CLASS_CONSTANT", .{ .int = 16 });
    try attr_def.static_props.put(a, "TARGET_PARAMETER", .{ .int = 32 });
    try attr_def.static_props.put(a, "TARGET_ALL", .{ .int = 127 });
    try attr_def.static_props.put(a, "IS_REPEATABLE", .{ .int = 128 });
    try vm.classes.put(a, "Attribute", attr_def);

    // ReflectionException
    var exc_def = ClassDef{ .name = "ReflectionException" };
    exc_def.parent = "Exception";
    try vm.classes.put(a, "ReflectionException", exc_def);

    // Reflection (utility class)
    var refl_def = ClassDef{ .name = "Reflection" };
    try refl_def.methods.put(a, "getModifierNames", .{ .name = "getModifierNames", .arity = 1, .is_static = true });
    try vm.classes.put(a, "Reflection", refl_def);
    try vm.native_fns.put(a, "Reflection::getModifierNames", reflectionGetModifierNames);

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
    try rc_def.methods.put(a, "isInstance", .{ .name = "isInstance", .arity = 1 });
    try rc_def.methods.put(a, "isFinal", .{ .name = "isFinal", .arity = 0 });
    try rc_def.methods.put(a, "isCloneable", .{ .name = "isCloneable", .arity = 0 });
    try rc_def.methods.put(a, "newInstanceArgs", .{ .name = "newInstanceArgs", .arity = 1 });
    try rc_def.methods.put(a, "getMethods", .{ .name = "getMethods", .arity = 1 });
    try rc_def.methods.put(a, "getMethod", .{ .name = "getMethod", .arity = 1 });
    try rc_def.methods.put(a, "hasMethod", .{ .name = "hasMethod", .arity = 1 });
    try rc_def.methods.put(a, "isAbstract", .{ .name = "isAbstract", .arity = 0 });
    try rc_def.methods.put(a, "isInterface", .{ .name = "isInterface", .arity = 0 });
    try rc_def.methods.put(a, "getInterfaceNames", .{ .name = "getInterfaceNames", .arity = 0 });
    try rc_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rc_def.methods.put(a, "getProperties", .{ .name = "getProperties", .arity = 0 });
    try rc_def.methods.put(a, "getProperty", .{ .name = "getProperty", .arity = 1 });
    try rc_def.methods.put(a, "hasProperty", .{ .name = "hasProperty", .arity = 1 });
    try rc_def.methods.put(a, "newInstanceWithoutConstructor", .{ .name = "newInstanceWithoutConstructor", .arity = 0 });
    try rc_def.methods.put(a, "getShortName", .{ .name = "getShortName", .arity = 0 });
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
    try vm.native_fns.put(a, "ReflectionClass::getMethods", rcGetMethods);
    try vm.native_fns.put(a, "ReflectionClass::getMethod", rcGetMethod);
    try vm.native_fns.put(a, "ReflectionClass::hasMethod", rcHasMethod);
    try vm.native_fns.put(a, "ReflectionClass::isAbstract", rcIsAbstract);
    try vm.native_fns.put(a, "ReflectionClass::isInterface", rcIsInterface);
    try vm.native_fns.put(a, "ReflectionClass::getInterfaceNames", rcGetInterfaceNames);
    try vm.native_fns.put(a, "ReflectionClass::getAttributes", rcGetAttributes);
    try vm.native_fns.put(a, "ReflectionClass::getProperties", rcGetProperties);
    try vm.native_fns.put(a, "ReflectionClass::getProperty", rcGetProperty);
    try vm.native_fns.put(a, "ReflectionClass::hasProperty", rcHasProperty);
    try vm.native_fns.put(a, "ReflectionClass::newInstanceWithoutConstructor", rcNewInstanceWithoutConstructor);
    try vm.native_fns.put(a, "ReflectionClass::getShortName", rcGetShortName);
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
    try vm.native_fns.put(a, "ReflectionClass::getDefaultProperties", rcGetDefaultProperties);
    try vm.native_fns.put(a, "ReflectionClass::getStaticProperties", rcGetStaticProperties);
    try vm.native_fns.put(a, "ReflectionClass::getStaticPropertyValue", rcGetStaticPropertyValue);
    try vm.native_fns.put(a, "ReflectionClass::setStaticPropertyValue", rcSetStaticPropertyValue);
    try vm.native_fns.put(a, "ReflectionClass::isFinal", rcIsFinal);
    try vm.native_fns.put(a, "ReflectionClass::isCloneable", rcIsCloneable);

    // ReflectionMethod
    var rm_def = ClassDef{ .name = "ReflectionMethod" };
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
    try rm_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rm_def.properties.append(a, .{ .name = "class", .default = .{ .string = "" } });
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
    try rm_def.methods.put(a, "getNumberOfParameters", .{ .name = "getNumberOfParameters", .arity = 0 });
    try rm_def.methods.put(a, "getNumberOfRequiredParameters", .{ .name = "getNumberOfRequiredParameters", .arity = 0 });
    try rm_def.methods.put(a, "setAccessible", .{ .name = "setAccessible", .arity = 1 });
    try rm_def.methods.put(a, "invoke", .{ .name = "invoke", .arity = 1 });
    try rm_def.methods.put(a, "hasReturnType", .{ .name = "hasReturnType", .arity = 0 });
    try rm_def.methods.put(a, "invokeArgs", .{ .name = "invokeArgs", .arity = 2 });
    try rm_def.methods.put(a, "isAbstract", .{ .name = "isAbstract", .arity = 0 });
    try rm_def.methods.put(a, "isFinal", .{ .name = "isFinal", .arity = 0 });
    try rm_def.methods.put(a, "getModifiers", .{ .name = "getModifiers", .arity = 0 });
    try rm_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
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
    try vm.native_fns.put(a, "ReflectionMethod::getNumberOfParameters", rmGetNumberOfParameters);
    try vm.native_fns.put(a, "ReflectionMethod::getNumberOfRequiredParameters", rmGetNumberOfRequiredParameters);
    try vm.native_fns.put(a, "ReflectionMethod::setAccessible", reflectionNoop);
    try vm.native_fns.put(a, "ReflectionMethod::invoke", rmInvoke);
    try vm.native_fns.put(a, "ReflectionMethod::hasReturnType", rmHasReturnType);
    try vm.native_fns.put(a, "ReflectionMethod::invokeArgs", rmInvokeArgs);
    try vm.native_fns.put(a, "ReflectionMethod::isAbstract", rmIsAbstract);
    try vm.native_fns.put(a, "ReflectionMethod::isFinal", rmIsFinal);
    try vm.native_fns.put(a, "ReflectionMethod::getModifiers", rmGetModifiers);
    try vm.native_fns.put(a, "ReflectionMethod::getAttributes", rmGetAttributes);

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
    try rp_def.methods.put(a, "canBePassedByValue", .{ .name = "canBePassedByValue", .arity = 0 });
    try rp_def.methods.put(a, "hasType", .{ .name = "hasType", .arity = 0 });
    try rp_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rp_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rp_def.methods.put(a, "isVariadic", .{ .name = "isVariadic", .arity = 0 });
    try rp_def.methods.put(a, "isPromoted", .{ .name = "isPromoted", .arity = 0 });
    try rp_def.methods.put(a, "getClass", .{ .name = "getClass", .arity = 0 });
    try vm.classes.put(a, "ReflectionParameter", rp_def);

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
    try vm.native_fns.put(a, "ReflectionParameter::isVariadic", rpIsVariadic);
    try vm.native_fns.put(a, "ReflectionParameter::isPromoted", rpIsPromoted);
    try vm.native_fns.put(a, "ReflectionParameter::getClass", rpGetClass);

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
    try vm.native_fns.put(a, "ReflectionNamedType::__toString", rntToString);

    // ReflectionUnionType
    var rut_def = ClassDef{ .name = "ReflectionUnionType" };
    try rut_def.properties.append(a, .{ .name = "type_str", .default = .{ .string = "" } });
    try rut_def.properties.append(a, .{ .name = "nullable", .default = .{ .bool = false } });
    try rut_def.methods.put(a, "getTypes", .{ .name = "getTypes", .arity = 0 });
    try rut_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rut_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionUnionType", rut_def);
    try vm.native_fns.put(a, "ReflectionUnionType::getTypes", rutGetTypes);
    try vm.native_fns.put(a, "ReflectionUnionType::allowsNull", rutAllowsNull);
    try vm.native_fns.put(a, "ReflectionUnionType::__toString", rutToString);

    // ReflectionIntersectionType
    var rit_def = ClassDef{ .name = "ReflectionIntersectionType" };
    try rit_def.properties.append(a, .{ .name = "type_str", .default = .{ .string = "" } });
    try rit_def.methods.put(a, "getTypes", .{ .name = "getTypes", .arity = 0 });
    try rit_def.methods.put(a, "allowsNull", .{ .name = "allowsNull", .arity = 0 });
    try rit_def.methods.put(a, "__toString", .{ .name = "__toString", .arity = 0 });
    try vm.classes.put(a, "ReflectionIntersectionType", rit_def);
    try vm.native_fns.put(a, "ReflectionIntersectionType::getTypes", ritGetTypes);
    try vm.native_fns.put(a, "ReflectionIntersectionType::allowsNull", ritAllowsNull);
    try vm.native_fns.put(a, "ReflectionIntersectionType::__toString", ritToString);

    // ReflectionEnum (extends ReflectionClass)
    var re_def = ClassDef{ .name = "ReflectionEnum" };
    re_def.parent = "ReflectionClass";
    try re_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
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

    // ReflectionEnumUnitCase
    var reuc_def = ClassDef{ .name = "ReflectionEnumUnitCase" };
    try reuc_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try reuc_def.properties.append(a, .{ .name = "class", .default = .{ .string = "" } });
    try reuc_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try reuc_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 0 });
    try vm.classes.put(a, "ReflectionEnumUnitCase", reuc_def);
    try vm.native_fns.put(a, "ReflectionEnumUnitCase::getName", reucGetName);
    try vm.native_fns.put(a, "ReflectionEnumUnitCase::getValue", reucGetValue);

    // ReflectionEnumBackedCase (extends ReflectionEnumUnitCase)
    var rebc_def = ClassDef{ .name = "ReflectionEnumBackedCase" };
    rebc_def.parent = "ReflectionEnumUnitCase";
    try rebc_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rebc_def.properties.append(a, .{ .name = "class", .default = .{ .string = "" } });
    try rebc_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rebc_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 0 });
    try rebc_def.methods.put(a, "getBackingValue", .{ .name = "getBackingValue", .arity = 0 });
    try vm.classes.put(a, "ReflectionEnumBackedCase", rebc_def);
    try vm.native_fns.put(a, "ReflectionEnumBackedCase::getName", reucGetName);
    try vm.native_fns.put(a, "ReflectionEnumBackedCase::getValue", reucGetValue);
    try vm.native_fns.put(a, "ReflectionEnumBackedCase::getBackingValue", rebcGetBackingValue);

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
    try rf_def.methods.put(a, "isClosure", .{ .name = "isClosure", .arity = 0 });
    try rf_def.methods.put(a, "getClosureScopeClass", .{ .name = "getClosureScopeClass", .arity = 0 });
    try rf_def.methods.put(a, "hasReturnType", .{ .name = "hasReturnType", .arity = 0 });
    try rf_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try vm.classes.put(a, "ReflectionFunction", rf_def);

    try vm.native_fns.put(a, "ReflectionFunction::__construct", rfConstruct);
    try vm.native_fns.put(a, "ReflectionFunction::getName", rfGetName);
    try vm.native_fns.put(a, "ReflectionFunction::getParameters", rfGetParameters);
    try vm.native_fns.put(a, "ReflectionFunction::getReturnType", rfGetReturnType);
    try vm.native_fns.put(a, "ReflectionFunction::getNumberOfParameters", rfGetNumberOfParameters);
    try vm.native_fns.put(a, "ReflectionFunction::getNumberOfRequiredParameters", rfGetNumberOfRequiredParameters);
    try vm.native_fns.put(a, "ReflectionFunction::isAnonymous", rfIsAnonymous);
    try vm.native_fns.put(a, "ReflectionFunction::isClosure", rfIsAnonymous);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureScopeClass", rfGetClosureScopeClass);
    try vm.native_fns.put(a, "ReflectionFunction::hasReturnType", rfHasReturnType);
    try vm.native_fns.put(a, "ReflectionFunction::getAttributes", rfGetAttributes);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureUsedVariables", rfGetClosureUsedVariables);
    try vm.native_fns.put(a, "ReflectionFunction::getClosureCalledClass", rfGetClosureCalledClass);

    // ReflectionProperty
    var rprop_def = ClassDef{ .name = "ReflectionProperty" };
    try rprop_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rprop_def.properties.append(a, .{ .name = "class", .default = .{ .string = "" } });
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
    try rprop_def.methods.put(a, "setValue", .{ .name = "setValue", .arity = 2 });
    try rprop_def.methods.put(a, "isStatic", .{ .name = "isStatic", .arity = 0 });
    try rprop_def.methods.put(a, "isPromoted", .{ .name = "isPromoted", .arity = 0 });
    try rprop_def.methods.put(a, "hasType", .{ .name = "hasType", .arity = 0 });
    try rprop_def.methods.put(a, "getModifiers", .{ .name = "getModifiers", .arity = 0 });
    try rprop_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rprop_def.methods.put(a, "getDocComment", .{ .name = "getDocComment", .arity = 0 });
    try rprop_def.methods.put(a, "isVirtual", .{ .name = "isVirtual", .arity = 0 });
    try vm.classes.put(a, "ReflectionProperty", rprop_def);

    try vm.native_fns.put(a, "ReflectionProperty::__construct", rpConstruct);
    try vm.native_fns.put(a, "ReflectionProperty::setAccessible", reflectionNoop);
    try vm.native_fns.put(a, "ReflectionProperty::getValue", rpGetValue);
    try vm.native_fns.put(a, "ReflectionProperty::setValue", rpSetValue);
    try vm.native_fns.put(a, "ReflectionProperty::getName", rpropGetName);
    try vm.native_fns.put(a, "ReflectionProperty::getType", rpropGetType);
    try vm.native_fns.put(a, "ReflectionProperty::isPublic", rpropIsPublic);
    try vm.native_fns.put(a, "ReflectionProperty::isProtected", rpropIsProtected);
    try vm.native_fns.put(a, "ReflectionProperty::isPrivate", rpropIsPrivate);
    try vm.native_fns.put(a, "ReflectionProperty::getDefaultValue", rpropGetDefaultValue);
    try vm.native_fns.put(a, "ReflectionProperty::hasDefaultValue", rpropHasDefaultValue);
    try vm.native_fns.put(a, "ReflectionProperty::isInitialized", rpropIsInitialized);
    try vm.native_fns.put(a, "ReflectionProperty::getDeclaringClass", rpropGetDeclaringClass);
    try vm.native_fns.put(a, "ReflectionProperty::isDefault", rpropIsDefault);
    try vm.native_fns.put(a, "ReflectionProperty::isReadOnly", rpropIsReadOnly);
    try vm.native_fns.put(a, "ReflectionProperty::isStatic", rpropIsStatic);
    try vm.native_fns.put(a, "ReflectionProperty::isPromoted", rpropIsPromoted);
    try vm.native_fns.put(a, "ReflectionProperty::hasType", rpropHasType);
    try vm.native_fns.put(a, "ReflectionProperty::getModifiers", rpropGetModifiers);
    try vm.native_fns.put(a, "ReflectionProperty::getAttributes", rpropGetAttributes);
    try vm.native_fns.put(a, "ReflectionProperty::getDocComment", rpropGetDocComment);
    try vm.native_fns.put(a, "ReflectionProperty::isVirtual", rpropIsVirtual);

    // ReflectionAttribute
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

    // ReflectionClassConstant
    var rcc_def = ClassDef{ .name = "ReflectionClassConstant" };
    try rcc_def.properties.append(a, .{ .name = "name", .default = .{ .string = "" } });
    try rcc_def.properties.append(a, .{ .name = "class", .default = .{ .string = "" } });
    try rcc_def.methods.put(a, "getName", .{ .name = "getName", .arity = 0 });
    try rcc_def.methods.put(a, "getValue", .{ .name = "getValue", .arity = 0 });
    try rcc_def.methods.put(a, "getDeclaringClass", .{ .name = "getDeclaringClass", .arity = 0 });
    try rcc_def.methods.put(a, "getAttributes", .{ .name = "getAttributes", .arity = 0 });
    try rcc_def.methods.put(a, "isPublic", .{ .name = "isPublic", .arity = 0 });
    try rcc_def.methods.put(a, "isProtected", .{ .name = "isProtected", .arity = 0 });
    try rcc_def.methods.put(a, "isPrivate", .{ .name = "isPrivate", .arity = 0 });
    try rcc_def.methods.put(a, "isFinal", .{ .name = "isFinal", .arity = 0 });
    try rcc_def.methods.put(a, "isEnumCase", .{ .name = "isEnumCase", .arity = 0 });
    try vm.classes.put(a, "ReflectionClassConstant", rcc_def);

    try vm.native_fns.put(a, "ReflectionClassConstant::getName", rccGetName);
    try vm.native_fns.put(a, "ReflectionClassConstant::getValue", rccGetValue);
    try vm.native_fns.put(a, "ReflectionClassConstant::getDeclaringClass", rccGetDeclaringClass);
    try vm.native_fns.put(a, "ReflectionClassConstant::getAttributes", rccGetAttributes);
    try vm.native_fns.put(a, "ReflectionClassConstant::isPublic", rccIsPublic);
    try vm.native_fns.put(a, "ReflectionClassConstant::isProtected", rccIsProtected);
    try vm.native_fns.put(a, "ReflectionClassConstant::isPrivate", rccIsPrivate);
    try vm.native_fns.put(a, "ReflectionClassConstant::isFinal", rccIsFinal);
    try vm.native_fns.put(a, "ReflectionClassConstant::isEnumCase", rccIsEnumCase);

    // Closure class (static methods only - instance methods handled in VM dispatch)
    var closure_def = ClassDef{ .name = "Closure" };
    try closure_def.methods.put(a, "bind", .{ .name = "bind", .arity = 2, .is_static = true });
    try closure_def.methods.put(a, "fromCallable", .{ .name = "fromCallable", .arity = 1, .is_static = true });
    try vm.classes.put(a, "Closure", closure_def);

    try vm.native_fns.put(a, "Closure::bind", closureBind);
    try vm.native_fns.put(a, "Closure::fromCallable", closureFromCallable);

    var rref_def = ClassDef{ .name = "ReflectionReference" };
    try rref_def.methods.put(a, "fromArrayElement", .{ .name = "fromArrayElement", .arity = 2, .is_static = true });
    try rref_def.methods.put(a, "getId", .{ .name = "getId", .arity = 0 });
    try vm.classes.put(a, "ReflectionReference", rref_def);

    try vm.native_fns.put(a, "ReflectionReference::fromArrayElement", rrefFromArrayElement);
    try vm.native_fns.put(a, "ReflectionReference::getId", rrefGetId);
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

fn createTypeObj(ctx: *NativeContext, type_name: []const u8, nullable: bool, self_class: ?[]const u8) !*PhpObject {
    var clean = type_name;
    var is_nullable = nullable;
    if (clean.len > 0 and clean[0] == '?') {
        clean = clean[1..];
        is_nullable = true;
    }
    // resolve self/static to declaring class
    if (self_class) |sc| {
        if (std.mem.eql(u8, clean, "self") or std.mem.eql(u8, clean, "static")) {
            clean = sc;
        }
    }
    if (std.mem.indexOfScalar(u8, clean, '|') != null) {
        const obj = try ctx.createObject("ReflectionUnionType");
        try obj.set(ctx.allocator, "type_str", .{ .string = clean });
        // detect null member for nullable
        var it = std.mem.splitScalar(u8, clean, '|');
        while (it.next()) |part| {
            if (std.mem.eql(u8, part, "null")) is_nullable = true;
        }
        try obj.set(ctx.allocator, "nullable", .{ .bool = is_nullable });
        try obj.set(ctx.allocator, "_self_class", .{ .string = self_class orelse "" });
        return obj;
    }
    if (std.mem.indexOfScalar(u8, clean, '&') != null) {
        const obj = try ctx.createObject("ReflectionIntersectionType");
        try obj.set(ctx.allocator, "type_str", .{ .string = clean });
        return obj;
    }
    return createNamedTypeObj(ctx, clean, is_nullable);
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

const PropertyDefResult = struct {
    prop: ClassDef.PropertyDef,
    declaring_class: []const u8,
};

fn findPropertyDef(vm: *VM, class_name: []const u8, prop_name: []const u8) ?PropertyDefResult {
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = vm.classes.get(name) orelse break;
        for (cls.properties.items) |prop| {
            if (std.mem.eql(u8, prop.name, prop_name)) return .{ .prop = prop, .declaring_class = name };
        }
        current = cls.parent;
    }
    return null;
}

fn buildPropertyObj(ctx: *NativeContext, class_name: []const u8, prop: ClassDef.PropertyDef, declaring_class: []const u8) !*PhpObject {
    const obj = try ctx.createObject("ReflectionProperty");
    try obj.set(ctx.allocator, "name", .{ .string = prop.name });
    try obj.set(ctx.allocator, "class", .{ .string = class_name });
    try obj.set(ctx.allocator, "_visibility", .{ .int = @intFromEnum(prop.visibility) });
    try obj.set(ctx.allocator, "_has_default", .{ .bool = prop.default != .null });
    try obj.set(ctx.allocator, "_default_value", prop.default);
    try obj.set(ctx.allocator, "_declaring_class", .{ .string = declaring_class });
    try obj.set(ctx.allocator, "_is_readonly", .{ .bool = prop.is_readonly });
    return obj;
}

fn hasAbstractMethodInChain(vm: *VM, class_name: []const u8, method_name: []const u8) bool {
    var current = class_name;
    while (true) {
        const cls = vm.classes.get(current) orelse return false;
        if (cls.methods.get(method_name)) |_| return true;
        if (cls.parent) |p| { current = p; continue; }
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

// --- ReflectionClass ---

fn rcConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return throwReflection(ctx, "ReflectionClass::__construct() expects a class name");
    const class_name = if (args[0] == .string)
        args[0].string
    else if (args[0] == .object)
        args[0].object.class_name
    else
        return throwReflection(ctx, "ReflectionClass::__construct() expects a class name or object");
    const this = getThis(ctx) orelse return .null;

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

    try this.set(ctx.allocator, "name", .{ .string = class_name });
    try this.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(class_name) });
    try this.set(ctx.allocator, "_is_trait", .{ .bool = ctx.vm.traits.contains(class_name) });
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
    const is_trait = this.get("_is_trait");
    if (is_trait == .bool and is_trait.bool) return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .bool = true };
    if (cls.is_abstract) return .{ .bool = false };
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

fn rcIsInstance(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .object) return .{ .bool = false };
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const obj_class = args[0].object.class_name;
    if (std.mem.eql(u8, obj_class, class_name)) return .{ .bool = true };
    if (ctx.vm.interfaces.contains(class_name)) {
        var current: ?[]const u8 = obj_class;
        while (current) |name| {
            const cls = ctx.vm.classes.get(name) orelse break;
            for (cls.interfaces.items) |iface| {
                if (std.mem.eql(u8, iface, class_name)) return .{ .bool = true };
            }
            current = cls.parent;
        }
        return .{ .bool = false };
    }
    var current: ?[]const u8 = obj_class;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.parent) |p| {
            if (std.mem.eql(u8, p, class_name)) return .{ .bool = true };
            current = p;
        } else break;
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

fn rcGetMethods(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const filter: ?i64 = if (args.len >= 1 and args[0] == .int) args[0].int else null;

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
                const info = entry.value_ptr.*;
                if (filter) |f| {
                    if (!methodMatchesFilter(info, f)) continue;
                }
                const declaring = findDeclaringClass(ctx.vm, class_name, method_name);
                const obj = try buildMethodObj(ctx, class_name, method_name, info, declaring);
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        }
        current = cls.parent;
    }
    return .{ .array = arr };
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
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .bool = false };
    return .{ .bool = cls.is_abstract };
}

fn rcIsFinal(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .bool = false };
    if (cls.is_enum) return .{ .bool = true };
    return .{ .bool = cls.is_final };
}

fn rcIsCloneable(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const is_iface = this.get("_is_interface");
    if (is_iface == .bool and is_iface.bool) return .{ .bool = false };
    const is_trait = this.get("_is_trait");
    if (is_trait == .bool and is_trait.bool) return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .bool = true };
    if (cls.is_abstract) return .{ .bool = false };
    if (cls.is_enum) return .{ .bool = false };
    if (cls.methods.get("__clone")) |m| {
        if (m.visibility != .public) return .{ .bool = false };
    }
    return .{ .bool = true };
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

fn buildReflectionAttribute(ctx: *NativeContext, attr: AttributeDef, target: i64, is_repeated: bool) RuntimeError!Value {
    const obj = try ctx.createObject("ReflectionAttribute");
    try obj.set(ctx.allocator, "name", .{ .string = attr.name });
    const args_arr = try ctx.createArray();
    for (attr.args, 0..) |arg, i| {
        if (i < attr.arg_names.len) {
            if (attr.arg_names[i]) |arg_name| {
                try args_arr.set(ctx.allocator, .{ .string = arg_name }, arg);
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

fn buildAttributeArray(ctx: *NativeContext, attrs: []const AttributeDef, filter: ?[]const u8, target: i64) RuntimeError!Value {
    const arr = try ctx.createArray();
    for (attrs) |attr| {
        if (filter) |f| {
            if (!std.mem.eql(u8, attr.name, f)) continue;
        }
        var count: usize = 0;
        for (attrs) |other| {
            if (std.mem.eql(u8, other.name, attr.name)) count += 1;
        }
        try arr.append(ctx.allocator, try buildReflectionAttribute(ctx, attr, target, count > 1));
    }
    return .{ .array = arr };
}

fn rcGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .array = try ctx.createArray() };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .array = try ctx.createArray() };
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string else null;
    return buildAttributeArray(ctx, cls.attributes.items, filter, 1); // TARGET_CLASS
}

fn rcGetProperties(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

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
                const obj = try buildPropertyObj(ctx, class_name, prop, name);
                try arr.append(ctx.allocator, .{ .object = obj });
            }
        }
        current = cls.parent;
        is_own = false;
    }
    return .{ .array = arr };
}

fn rcGetProperty(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::getProperty() expects a property name");
    const prop_name = args[0].string;
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    if (findPropertyDef(ctx.vm, class_name, prop_name)) |result| {
        const obj = try buildPropertyObj(ctx, class_name, result.prop, result.declaring_class);
        return .{ .object = obj };
    }
    const msg = std.fmt.allocPrint(ctx.allocator, "Property {s}::${s} does not exist", .{ class_name, prop_name }) catch return error.OutOfMemory;
    return throwReflection(ctx, msg);
}

fn rcHasProperty(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    return .{ .bool = findPropertyDef(ctx.vm, class_name, args[0].string) != null };
}

fn rcNewInstanceWithoutConstructor(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const obj = try ctx.vm.allocator.create(PhpObject);
    obj.* = .{ .class_name = class_name };
    try ctx.vm.objects.append(ctx.vm.allocator, obj);

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        for (cls.properties.items) |prop| {
            if (obj.get(prop.name) == .null) {
                try obj.set(ctx.vm.allocator, prop.name, prop.default);
            }
        }
        current = cls.parent;
    }
    return .{ .object = obj };
}

fn rcGetShortName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const name = if (this.get("name") == .string) this.get("name").string else return .null;
    if (std.mem.lastIndexOfScalar(u8, name, '\\')) |pos| {
        return .{ .string = name[pos + 1 ..] };
    }
    return .{ .string = name };
}

fn rcIsTrait(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const v = this.get("_is_trait");
    return .{ .bool = v == .bool and v.bool };
}

fn rcGetTraitNames(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .array = try ctx.createArray() };

    const arr = try ctx.createArray();
    for (cls.used_traits.items) |name| {
        try arr.append(ctx.allocator, .{ .string = name });
    }
    return .{ .array = arr };
}

fn rcIsEnum(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(name) orelse return .{ .bool = false };
    return .{ .bool = cls.is_enum };
}

fn rcGetConstants(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const arr = try ctx.createArray();
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        var it = cls.constant_names.iterator();
        while (it.next()) |entry| {
            if (cls.static_props.get(entry.key_ptr.*)) |val| {
                try arr.set(ctx.allocator, .{ .string = entry.key_ptr.* }, val);
            }
        }
        current = cls.parent;
    }
    return .{ .array = arr };
}

fn rcGetReflectionConstants(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const arr = try ctx.createArray();
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        var it = cls.constant_names.iterator();
        while (it.next()) |entry| {
            const cname = entry.key_ptr.*;
            if (cls.static_props.get(cname)) |val| {
                const obj = try buildReflectionClassConstant(ctx, name, cname, val);
                try arr.append(ctx.allocator, obj);
            }
        }
        current = cls.parent;
    }
    return .{ .array = arr };
}

fn rcGetReflectionConstant(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const target = args[0].string;

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constant_names.contains(target)) {
            if (cls.static_props.get(target)) |val| {
                return try buildReflectionClassConstant(ctx, name, target, val);
            }
        }
        current = cls.parent;
    }
    return .{ .bool = false };
}

fn rcHasConstant(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const target = args[0].string;

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constant_names.contains(target)) return .{ .bool = true };
        current = cls.parent;
    }
    return .{ .bool = false };
}

fn rcGetConstant(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    if (args.len == 0 or args[0] != .string) return .{ .bool = false };
    const target = args[0].string;

    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (cls.constant_names.contains(target)) {
            if (cls.static_props.get(target)) |val| return val;
        }
        current = cls.parent;
    }
    return .{ .bool = false };
}

fn buildReflectionClassConstant(ctx: *NativeContext, class_name: []const u8, const_name: []const u8, value: Value) RuntimeError!Value {
    const obj = try ctx.createObject("ReflectionClassConstant");
    try obj.set(ctx.allocator, "name", .{ .string = const_name });
    try obj.set(ctx.allocator, "class", .{ .string = class_name });
    try obj.set(ctx.allocator, "_value", value);
    return .{ .object = obj };
}

fn rccGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("name");
}

fn rccGetValue(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("_value");
}

fn rccGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("class") == .string) this.get("class").string else return .null;
    const rc = try ctx.createObject("ReflectionClass");
    try rc.set(ctx.allocator, "name", .{ .string = class_name });
    return .{ .object = rc };
}

fn rccGetAttributes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("class") == .string) this.get("class").string else return .null;
    const const_name = if (this.get("name") == .string) this.get("name").string else return .null;

    const cls = ctx.vm.classes.get(class_name) orelse {
        return .{ .array = try ctx.createArray() };
    };
    if (cls.constant_attributes.get(const_name)) |attrs| {
        return try buildAttributeArray(ctx, attrs, null, 16);
    }
    return .{ .array = try ctx.createArray() };
}

fn rccIsPublic(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn rccIsProtected(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rccIsPrivate(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rccIsFinal(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rccIsEnumCase(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("class") == .string) this.get("class").string else return .{ .bool = false };
    const const_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .bool = false };
    if (!cls.is_enum) return .{ .bool = false };
    for (cls.case_order.items) |case_name| {
        if (std.mem.eql(u8, case_name, const_name)) return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn rcIsInternal(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rcIsUserDefined(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn rcGetFileName(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rcGetStartLine(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rcGetDefaultProperties(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const arr = try ctx.createArray();
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .array = arr };
    for (cls.properties.items) |prop| {
        try arr.set(ctx.allocator, .{ .string = prop.name }, prop.default);
    }
    return .{ .array = arr };
}

fn rcGetStaticProperties(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const arr = try ctx.createArray();
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        var it = cls.static_props.iterator();
        while (it.next()) |entry| {
            if (cls.constant_names.contains(entry.key_ptr.*)) continue;
            try arr.set(ctx.allocator, .{ .string = entry.key_ptr.* }, entry.value_ptr.*);
        }
        current = cls.parent;
    }
    return .{ .array = arr };
}

fn rcGetStaticPropertyValue(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::getStaticPropertyValue() expects a property name");
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const prop_name = args[0].string;
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls = ctx.vm.classes.get(name) orelse break;
        if (!cls.constant_names.contains(prop_name)) {
            if (cls.static_props.get(prop_name)) |v| return v;
        }
        current = cls.parent;
    }
    if (args.len >= 2) return args[1];
    return throwReflection(ctx, "Static property does not exist");
}

fn rcSetStaticPropertyValue(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string) return throwReflection(ctx, "ReflectionClass::setStaticPropertyValue() expects a property name and value");
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const prop_name = args[0].string;
    var current: ?[]const u8 = class_name;
    while (current) |name| {
        const cls_ptr = ctx.vm.classes.getPtr(name) orelse break;
        if (!cls_ptr.constant_names.contains(prop_name)) {
            if (cls_ptr.static_props.contains(prop_name)) {
                try cls_ptr.static_props.put(ctx.vm.allocator, prop_name, args[1]);
                return .null;
            }
        }
        current = cls_ptr.parent;
    }
    return throwReflection(ctx, "Static property does not exist");
}


// --- ReflectionMethod ---

fn rmConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return throwReflection(ctx, "ReflectionMethod::__construct() expects parameters");
    const this = getThis(ctx) orelse return .null;

    var class_name: []const u8 = undefined;
    var method_name: []const u8 = undefined;

    if (args.len >= 2 and args[1] == .string) {
        method_name = args[1].string;
        if (args[0] == .string) {
            class_name = args[0].string;
        } else if (args[0] == .object) {
            class_name = args[0].object.class_name;
        } else {
            return throwReflection(ctx, "ReflectionMethod::__construct() expects a class name or object");
        }
    } else if (args[0] == .string) {
        // "Class::method" string form
        const s = args[0].string;
        if (std.mem.indexOf(u8, s, "::")) |sep| {
            class_name = s[0..sep];
            method_name = s[sep + 2 ..];
        } else {
            return throwReflection(ctx, "ReflectionMethod::__construct() expects Class::method format");
        }
    } else {
        return throwReflection(ctx, "ReflectionMethod::__construct() expects a class name or object");
    }

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

    try this.set(ctx.allocator, "name", .{ .string = method_name });
    try this.set(ctx.allocator, "class", .{ .string = class_name });
    try this.set(ctx.allocator, "_declaring_class", .{ .string = declaring });
    try this.set(ctx.allocator, "_is_static", .{ .bool = info.is_static });
    try this.set(ctx.allocator, "_visibility", .{ .int = @intFromEnum(info.visibility) });

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return .null;
    if (ctx.vm.functions.get(key)) |func| {
        try this.set(ctx.allocator, "_arity", .{ .int = func.arity });
        try this.set(ctx.allocator, "_required_params", .{ .int = func.required_params });
    } else {
        try this.set(ctx.allocator, "_arity", .{ .int = info.arity });
        try this.set(ctx.allocator, "_required_params", .{ .int = info.arity });
    }

    return .null;
}

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

    const obj = try createTypeObj(ctx, type_info.return_type, false, declaring);
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
    const declaring = this.get("_declaring_class");
    const self_class: ?[]const u8 = if (declaring == .string and declaring.string.len > 0) declaring.string else null;
    const obj = try createTypeObj(ctx, type_val.string, is_nullable, self_class);
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

fn rpCanBePassedByValue(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = true };
    const by_ref = this.get("_by_reference");
    return .{ .bool = !(by_ref == .bool and by_ref.bool) };
}

fn rpHasType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const type_val = this.get("_type_name");
    return .{ .bool = type_val == .string and type_val.string.len > 0 };
}

fn rpGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const param_name = if (this.get("name") == .string) this.get("name").string else return .{ .array = try ctx.createArray() };
    const class_name = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .{ .array = try ctx.createArray() };
    const method_name = if (this.get("_method_name") == .string) this.get("_method_name").string else return .{ .array = try ctx.createArray() };

    const cls = ctx.vm.classes.get(class_name) orelse return .{ .array = try ctx.createArray() };

    var key_buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{s}:{s}", .{ method_name, param_name }) catch return .{ .array = try ctx.createArray() };
    const attrs = cls.param_attributes.get(key) orelse return .{ .array = try ctx.createArray() };

    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string else null;
    return buildAttributeArray(ctx, attrs, filter, 32); // TARGET_PARAMETER
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

fn rntToString(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const name_v = this.get("type_name");
    if (name_v != .string) return name_v;
    const nullable_v = this.get("nullable");
    const is_nullable = nullable_v == .bool and nullable_v.bool;
    if (!is_nullable or std.mem.eql(u8, name_v.string, "mixed") or std.mem.eql(u8, name_v.string, "null")) return name_v;
    const result = std.fmt.allocPrint(ctx.allocator, "?{s}", .{name_v.string}) catch return name_v;
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
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

// --- ReflectionUnionType ---

fn rutGetTypes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const ts_v = this.get("type_str");
    if (ts_v != .string) return .{ .array = try ctx.createArray() };
    const sc_v = this.get("_self_class");
    const self_class: ?[]const u8 = if (sc_v == .string and sc_v.string.len > 0) sc_v.string else null;
    const arr = try ctx.createArray();
    var it = std.mem.splitScalar(u8, ts_v.string, '|');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const obj = try createNamedTypeObj(ctx, part, false);
        // resolve self/static
        if (self_class) |sc| {
            if (std.mem.eql(u8, part, "self") or std.mem.eql(u8, part, "static")) {
                try obj.set(ctx.allocator, "type_name", .{ .string = sc });
            }
        }
        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return .{ .array = arr };
}

fn rutAllowsNull(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const nullable = this.get("nullable");
    return .{ .bool = nullable == .bool and nullable.bool };
}

fn rutToString(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const ts_v = this.get("type_str");
    return ts_v;
}

// --- ReflectionIntersectionType ---

fn ritGetTypes(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const ts_v = this.get("type_str");
    if (ts_v != .string) return .{ .array = try ctx.createArray() };
    const arr = try ctx.createArray();
    var it = std.mem.splitScalar(u8, ts_v.string, '&');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const obj = try createNamedTypeObj(ctx, part, false);
        try arr.append(ctx.allocator, .{ .object = obj });
    }
    return .{ .array = arr };
}

fn ritAllowsNull(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn ritToString(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const ts_v = this.get("type_str");
    return ts_v;
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

    const type_info = closureAwareTypeInfo(func_name) orelse return .null;
    if (type_info.return_type.len == 0) return .null;

    const obj = try createTypeObj(ctx, type_info.return_type, false, null);
    return .{ .object = obj };
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

fn rfHasReturnType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const func_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };

    const type_info = closureAwareTypeInfo(func_name) orelse return .{ .bool = false };
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

fn rfGetClosureUsedVariables(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .array = try ctx.createArray() };
}

fn rfGetClosureCalledClass(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    if (this.get("__scope_class") == .string) {
        const scope_name = this.get("__scope_class").string;
        const obj = try ctx.createObject("ReflectionClass");
        try obj.set(ctx.allocator, "name", .{ .string = scope_name });
        return .{ .object = obj };
    }
    return .null;
}

fn rfGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const func_name = if (this.get("name") == .string) this.get("name").string else return .{ .array = try ctx.createArray() };
    const compile_name = ctx.vm.getOrigClosureName(func_name);
    const attrs = ctx.vm.function_attributes.get(compile_name) orelse return .{ .array = try ctx.createArray() };
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string else null;
    return buildAttributeArray(ctx, attrs, filter, 2); // TARGET_FUNCTION
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

        // variadic
        const is_variadic = func.is_variadic and i == func.arity - 1;
        try obj.set(ctx.allocator, "_is_variadic", .{ .bool = is_variadic });

        // default values - defaults array has one entry per param, non-default params have .null
        // variadic params never have a default (they collect remaining args)
        const has_default = !is_variadic and i >= func.required_params;
        try obj.set(ctx.allocator, "_has_default", .{ .bool = has_default });
        if (has_default and i < func.defaults.len) {
            const raw = func.defaults[i];
            try obj.set(ctx.allocator, "_default_value", try ctx.vm.resolveDefault(raw));
        }

        // by-reference
        const by_ref = if (i < func.ref_params.len) func.ref_params[i] else false;
        try obj.set(ctx.allocator, "_by_reference", .{ .bool = by_ref });

        // declaring class and method name
        if (std.mem.indexOf(u8, type_key, "::")) |sep| {
            const decl_class = try ctx.allocator.dupe(u8, type_key[0..sep]);
            try ctx.strings.append(ctx.allocator, decl_class);
            try obj.set(ctx.allocator, "_declaring_class", .{ .string = decl_class });
            const meth_name = try ctx.allocator.dupe(u8, type_key[sep + 2 ..]);
            try ctx.strings.append(ctx.allocator, meth_name);
            try obj.set(ctx.allocator, "_method_name", .{ .string = meth_name });
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

fn rrefFromArrayElement(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn rrefGetId(_: *NativeContext, _: []const Value) RuntimeError!Value {
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

    if (findPropertyDef(ctx.vm, class_name, prop_name)) |result| {
        try this.set(ctx.allocator, "_visibility", .{ .int = @intFromEnum(result.prop.visibility) });
        try this.set(ctx.allocator, "_has_default", .{ .bool = result.prop.default != .null });
        try this.set(ctx.allocator, "_default_value", result.prop.default);
        try this.set(ctx.allocator, "_declaring_class", .{ .string = result.declaring_class });
        try this.set(ctx.allocator, "_is_readonly", .{ .bool = result.prop.is_readonly });
    } else {
        try this.set(ctx.allocator, "_visibility", .{ .int = 0 });
        try this.set(ctx.allocator, "_has_default", .{ .bool = false });
        try this.set(ctx.allocator, "_declaring_class", .{ .string = class_name });
        try this.set(ctx.allocator, "_is_readonly", .{ .bool = false });
    }
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

fn rpropGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("name");
}

fn rpropGetType(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .null;
}

fn rpropIsPublic(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = true };
    const vis = this.get("_visibility");
    return .{ .bool = vis == .int and vis.int == 0 };
}

fn rpropIsProtected(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const vis = this.get("_visibility");
    return .{ .bool = vis == .int and vis.int == 1 };
}

fn rpropIsPrivate(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const vis = this.get("_visibility");
    return .{ .bool = vis == .int and vis.int == 2 };
}

fn rpropGetDefaultValue(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const has_default = this.get("_has_default");
    if (has_default != .bool or !has_default.bool) return throwReflection(ctx, "Property does not have a default value");
    return this.get("_default_value");
}

fn rpropHasDefaultValue(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const has_default = this.get("_has_default");
    return .{ .bool = has_default == .bool and has_default.bool };
}

fn rpropIsInitialized(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const prop_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    if (args.len > 0 and args[0] == .object) {
        return .{ .bool = args[0].object.get(prop_name) != .null };
    }
    return .{ .bool = true };
}

fn rpropGetDeclaringClass(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .null;

    const obj = try ctx.createObject("ReflectionClass");
    try obj.set(ctx.allocator, "name", .{ .string = declaring });
    try obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(declaring) });
    return .{ .object = obj };
}

fn rpropIsDefault(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = true };
}

fn rpropIsReadOnly(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const v = this.get("_is_readonly");
    return .{ .bool = v == .bool and v.bool };
}

fn rpropIsStatic(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rpropIsPromoted(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rpropHasType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const t = this.get("_type");
    return .{ .bool = t != .null };
}

fn rpropGetModifiers(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .int = 0 };
    const vis = this.get("_visibility");
    if (vis == .int) {
        return switch (vis.int) {
            0 => .{ .int = 1 },
            1 => .{ .int = 2 },
            2 => .{ .int = 4 },
            else => .{ .int = 1 },
        };
    }
    return .{ .int = 1 };
}

fn rpropGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const prop_name = if (this.get("name") == .string) this.get("name").string else return .{ .array = try ctx.createArray() };
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .{ .array = try ctx.createArray() };
    const cls = ctx.vm.classes.get(declaring) orelse return .{ .array = try ctx.createArray() };
    const attrs = cls.property_attributes.get(prop_name) orelse return .{ .array = try ctx.createArray() };
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string else null;
    return buildAttributeArray(ctx, attrs, filter, 8); // TARGET_PROPERTY
}

fn rpropGetDocComment(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rpropIsVirtual(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

// --- ReflectionMethod::invoke ---

fn rmInvoke(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const method_name = if (this.get("name") == .string) this.get("name").string else return .null;
    if (args.len > 0 and args[0] == .object) {
        return ctx.callMethod(args[0].object, method_name, args[1..]) catch .null;
    }
    return .null;
}

fn rmInvokeArgs(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const method_name = if (this.get("name") == .string) this.get("name").string else return .null;
    if (args.len < 1) return .null;
    const target = args[0];
    if (target != .object) return .null;

    if (args.len >= 2 and args[1] == .array) {
        const arg_arr = args[1].array;
        var call_args: [16]Value = undefined;
        const count = @min(arg_arr.entries.items.len, 16);
        for (0..count) |i| {
            call_args[i] = arg_arr.entries.items[i].value;
        }
        return ctx.callMethod(target.object, method_name, call_args[0..count]) catch .null;
    }
    return ctx.callMethod(target.object, method_name, &.{}) catch .null;
}

fn rmIsAbstract(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const method_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .{ .bool = false };

    if (ctx.vm.interfaces.contains(declaring)) return .{ .bool = true };

    if (ctx.vm.classes.get(declaring)) |cls| {
        if (cls.methods.get(method_name)) |m| {
            if (m.is_abstract) return .{ .bool = true };
        }
    }

    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ declaring, method_name }) catch return .{ .bool = false };
    if (ctx.vm.functions.get(key) == null and ctx.vm.native_fns.get(key) == null) return .{ .bool = true };
    return .{ .bool = false };
}

fn rmIsFinal(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const method_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(declaring) orelse return .{ .bool = false };
    const m = cls.methods.get(method_name) orelse return .{ .bool = false };
    return .{ .bool = m.is_final };
}

fn rmGetModifiers(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .int = 0 };
    const method_name = if (this.get("name") == .string) this.get("name").string else return .{ .int = 0 };
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .{ .int = 0 };
    const cls = ctx.vm.classes.get(declaring) orelse return .{ .int = 0 };
    const info = cls.methods.get(method_name) orelse return .{ .int = 0 };
    return .{ .int = methodModifiers(info) };
}

fn reflectionGetModifierNames(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .int) return .{ .array = try ctx.createArray() };
    const m = args[0].int;
    const arr = try ctx.createArray();
    if ((m & 16) != 0) try arr.append(ctx.allocator, .{ .string = "static" });
    if ((m & 64) != 0) try arr.append(ctx.allocator, .{ .string = "abstract" });
    if ((m & 32) != 0) try arr.append(ctx.allocator, .{ .string = "final" });
    if ((m & 4) != 0) try arr.append(ctx.allocator, .{ .string = "private" });
    if ((m & 2) != 0) try arr.append(ctx.allocator, .{ .string = "protected" });
    if ((m & 1) != 0) try arr.append(ctx.allocator, .{ .string = "public" });
    return .{ .array = arr };
}

fn rmGetAttributes(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const method_name = if (this.get("name") == .string) this.get("name").string else return .{ .array = try ctx.createArray() };
    const declaring = if (this.get("_declaring_class") == .string) this.get("_declaring_class").string else return .{ .array = try ctx.createArray() };
    const cls = ctx.vm.classes.get(declaring) orelse return .{ .array = try ctx.createArray() };
    const attrs = cls.method_attributes.get(method_name) orelse return .{ .array = try ctx.createArray() };
    const filter: ?[]const u8 = if (args.len >= 1 and args[0] == .string) args[0].string else null;
    return buildAttributeArray(ctx, attrs, filter, 4); // TARGET_METHOD
}

fn rpIsPromoted(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .bool = false };
}

fn rpGetClass(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const type_val = this.get("_type_name");
    if (type_val != .string or type_val.string.len == 0) return .null;
    if (isBuiltinType(type_val.string)) return .null;

    if (ctx.vm.classes.contains(type_val.string) or ctx.vm.interfaces.contains(type_val.string)) {
        const obj = try ctx.createObject("ReflectionClass");
        try obj.set(ctx.allocator, "name", type_val);
        try obj.set(ctx.allocator, "_is_interface", .{ .bool = ctx.vm.interfaces.contains(type_val.string) });
        return .{ .object = obj };
    }
    return .null;
}

// --- ReflectionAttribute ---

fn raGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("name");
}

fn raGetArguments(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const args = this.get("_arguments");
    if (args == .array) return args;
    return .{ .array = try ctx.createArray() };
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

fn raNewInstance(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const name_val = this.get("name");
    if (name_val != .string) return .null;
    const attr_name = name_val.string;

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

    // target enforcement
    const target_val = this.get("_target");
    if (target_val == .int) {
        const target = target_val.int;
        const flags = getAttributeFlags(ctx.vm, attr_name);
        if (flags != 127 and (flags & target) == 0) {
            const msg = std.fmt.allocPrint(ctx.allocator, "Attribute \"{s}\" cannot target this declaration", .{attr_name}) catch return error.OutOfMemory;
            try ctx.strings.append(ctx.allocator, msg);
            _ = ctx.vm.throwBuiltinException("Error", msg) catch {};
            return error.RuntimeError;
        }
    }

    // repeatability enforcement
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
    if (args_val == .array) {
        const arr = args_val.array;
        var has_named = false;
        for (arr.entries.items) |entry| {
            if (entry.key == .string) { has_named = true; break; }
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
                            if (std.mem.eql(u8, pn, entry.key.string)) {
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
                if (pos > 0) {
                    _ = ctx.callMethod(obj, "__construct", resolved[0..pos]) catch {};
                }
            } else {
                var call_args: [16]Value = undefined;
                const count = @min(arr.entries.items.len, 16);
                for (0..count) |i| call_args[i] = arr.entries.items[i].value;
                if (count > 0) _ = ctx.callMethod(obj, "__construct", call_args[0..count]) catch {};
            }
        } else {
            var call_args: [16]Value = undefined;
            const count = @min(arr.entries.items.len, 16);
            for (0..count) |i| call_args[i] = arr.entries.items[i].value;
            if (count > 0) _ = ctx.callMethod(obj, "__construct", call_args[0..count]) catch {};
        }
    }
    return .{ .object = obj };
}

fn raGetTarget(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .int = 0 };
    const target = this.get("_target");
    return if (target == .int) target else .{ .int = 0 };
}

fn raIsRepeated(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const repeated = this.get("_is_repeated");
    return if (repeated == .bool) repeated else .{ .bool = false };
}

// --- ReflectionEnum ---

fn reConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1) return throwReflection(ctx, "ReflectionEnum::__construct() expects an enum name");
    const class_name = if (args[0] == .string)
        args[0].string
    else if (args[0] == .object)
        args[0].object.class_name
    else
        return throwReflection(ctx, "ReflectionEnum::__construct() expects an enum name or object");
    const this = getThis(ctx) orelse return .null;

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

    try this.set(ctx.allocator, "name", .{ .string = class_name });
    try this.set(ctx.allocator, "_is_interface", .{ .bool = false });
    try this.set(ctx.allocator, "_is_trait", .{ .bool = false });
    return .null;
}

fn reIsBacked(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .bool = false };
    return .{ .bool = cls.backed_type != .none };
}

fn reGetBackingType(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const cls = ctx.vm.classes.get(class_name) orelse return .null;
    const type_name: []const u8 = switch (cls.backed_type) {
        .none => return .null,
        .int_type => "int",
        .string_type => "string",
    };
    const obj = try createNamedTypeObj(ctx, type_name, false);
    return .{ .object = obj };
}

fn reGetCases(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .{ .array = try ctx.createArray() };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .array = try ctx.createArray() };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .array = try ctx.createArray() };
    const arr = try ctx.createArray();
    for (cls.case_order.items) |case_name| {
        const case_obj = try buildEnumCase(ctx, class_name, case_name, cls.backed_type != .none);
        try arr.append(ctx.allocator, .{ .object = case_obj });
    }
    return .{ .array = arr };
}

fn reGetCase(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return throwReflection(ctx, "ReflectionEnum::getCase() expects a name");
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const cls = ctx.vm.classes.get(class_name) orelse return .null;
    if (!cls.constant_names.contains(args[0].string)) {
        const msg = std.fmt.allocPrint(ctx.allocator, "Case {s}::{s} does not exist", .{ class_name, args[0].string }) catch return throwReflection(ctx, "Case not found");
        try ctx.strings.append(ctx.allocator, msg);
        return throwReflection(ctx, msg);
    }
    const obj = try buildEnumCase(ctx, class_name, args[0].string, cls.backed_type != .none);
    return .{ .object = obj };
}

fn reHasCase(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 1 or args[0] != .string) return .{ .bool = false };
    const this = getThis(ctx) orelse return .{ .bool = false };
    const class_name = if (this.get("name") == .string) this.get("name").string else return .{ .bool = false };
    const cls = ctx.vm.classes.get(class_name) orelse return .{ .bool = false };
    for (cls.case_order.items) |case_name| {
        if (std.mem.eql(u8, case_name, args[0].string)) return .{ .bool = true };
    }
    return .{ .bool = false };
}

fn buildEnumCase(ctx: *NativeContext, class_name: []const u8, case_name: []const u8, is_backed: bool) !*PhpObject {
    const obj_class: []const u8 = if (is_backed) "ReflectionEnumBackedCase" else "ReflectionEnumUnitCase";
    const obj = try ctx.createObject(obj_class);
    try obj.set(ctx.allocator, "name", .{ .string = case_name });
    try obj.set(ctx.allocator, "class", .{ .string = class_name });
    return obj;
}

fn reucGetName(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    return this.get("name");
}

fn reucGetValue(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("class") == .string) this.get("class").string else return .null;
    const case_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const cls = ctx.vm.classes.get(class_name) orelse return .null;
    return cls.static_props.get(case_name) orelse .null;
}

fn rebcGetBackingValue(ctx: *NativeContext, _: []const Value) RuntimeError!Value {
    const this = getThis(ctx) orelse return .null;
    const class_name = if (this.get("class") == .string) this.get("class").string else return .null;
    const case_name = if (this.get("name") == .string) this.get("name").string else return .null;
    const cls = ctx.vm.classes.get(class_name) orelse return .null;
    const case_obj_v = cls.static_props.get(case_name) orelse return .null;
    if (case_obj_v != .object) return .null;
    return case_obj_v.object.get("value");
}
