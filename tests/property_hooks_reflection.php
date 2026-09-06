<?php
class HookReflectionBase {
    public int $plain = 1;
    public int $number = 2 {
        get => $this->number * 2;
        set { $this->number = $value + 1; }
    }
    public string $virtual { get => 'virtual'; }
    public string $write { set {} }
}
class HookReflectionChild extends HookReflectionBase {}
foreach (PropertyHookType::cases() as $case) {
    echo get_class($case), ':', $case->name, ':', (int)($case instanceof UnitEnum), "\n";
}
foreach (['plain', 'number', 'virtual', 'write'] as $name) {
    $rp = new ReflectionProperty(HookReflectionChild::class, $name);
    echo $name, ':', (int)$rp->hasHooks(), ':', (int)$rp->hasHook(PropertyHookType::Get), ':', (int)$rp->hasHook(PropertyHookType::Set), "\n";
    foreach ($rp->getHooks() as $kind => $method) {
        echo $kind, ':', get_class($method), ':', $method->getName(), ':', $method->name, ':', $method->class, ':', $method->getDeclaringClass()->getName(), ':', $method->getNumberOfParameters(), ':', $method->getNumberOfRequiredParameters(), ':', $method->getModifiers(), ':', (int)$method->isPublic(), ':', (int)$method->hasReturnType(), ':', (string)$method->getReturnType(), "\n";
        foreach ($method->getParameters() as $p) echo $p->getName(), ':', $p->getDeclaringFunction()->getName(), "\n";
    }
    foreach ([PropertyHookType::Get, PropertyHookType::Set] as $kind) {
        $hook = $rp->getHook($kind);
        echo $hook === null ? 'none' : $hook->getName(), "\n";
    }
}
$obj = new HookReflectionChild;
$rp = new ReflectionProperty($obj, 'number');
$get = $rp->getHook(PropertyHookType::Get);
$set = $rp->getHook(PropertyHookType::Set);
echo $get->invoke($obj), "\n";
$set->invoke($obj, 5);
echo $get->invokeArgs($obj, []), "\n";
$set->invokeArgs($obj, [8]);
echo $obj->number, "\n";
foreach (['hasHook', 'getHook'] as $method) {
    try { $rp->$method('get'); } catch (TypeError $e) { echo "TypeError\n"; }
}
