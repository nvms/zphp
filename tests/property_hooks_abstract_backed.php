<?php
abstract class HookContract {
    abstract public int $value { get; set; }
}
class BackedContract extends HookContract { public int $value = 3; }
class BackedGrandchild extends BackedContract {}
foreach ([new BackedContract, new BackedGrandchild] as $object) {
    echo $object->value, "\n";
    $object->value = 9;
    echo $object->value, "\n";
    var_dump((new ReflectionProperty($object, 'value'))->hasHooks());
}
class ConcreteGetter { public int $value { get => 17; } }
class RetainedGetter extends ConcreteGetter { public int $value = 2; }
echo (new RetainedGetter)->value, "\n";
echo (new ReflectionProperty(RetainedGetter::class, 'value'))->getHook(PropertyHookType::Get)->getDeclaringClass()->getName(), "\n";
interface PropertyContract { public int $number { get; set; } }
class PropertyImplementation implements PropertyContract { public int $number = 4; }
$object = new PropertyImplementation;
echo $object->number, "\n";
$object->number = 7;
echo $object->number, "\n";
$property = new ReflectionProperty(PropertyContract::class, 'number');
echo $property->getName(), ':', $property->getType(), "\n";
var_dump($property->hasHooks(), $property->isAbstract());
foreach ($property->getHooks() as $kind => $hook) {
    echo $kind, ':', $hook->getName(), ':', $hook->getDeclaringClass()->getName(), "\n";
    var_dump($hook->isAbstract());
}
interface OtherPropertyContract { public string $label { get; } }
interface CombinedPropertyContract extends PropertyContract, OtherPropertyContract {}
foreach ((new ReflectionClass(CombinedPropertyContract::class))->getProperties() as $property) {
    echo $property->getName(), ':', $property->getDeclaringClass()->getName(), "\n";
}
$property = new ReflectionProperty(CombinedPropertyContract::class, 'number');
echo $property->getDeclaringClass()->getName(), ':', $property->getHook(PropertyHookType::Get)->getDeclaringClass()->getName(), "\n";
