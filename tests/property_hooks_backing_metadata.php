<?php
interface MetadataContract { public int $x { get; set; } }
abstract class MetadataBase { abstract public int $x { get; set; } }
class MetadataBacked extends MetadataBase { public int $x = 3 { get => $this->x; } }
class MetadataVirtual { public int $x { get => 7; } }
class MetadataShortSet { public int $x { set => $value; } }
class MetadataOther { public int $other = 1; public int $x { get => $this->other; } }
trait MetadataTrait { public int $x { get => $this->x; } }
class MetadataTraitUser { use MetadataTrait; }
foreach ([MetadataContract::class, MetadataBase::class, MetadataBacked::class, MetadataVirtual::class, MetadataShortSet::class, MetadataOther::class, MetadataTraitUser::class] as $class) {
    $p = new ReflectionProperty($class, 'x');
    echo $class, ':', (int)$p->isVirtual(), ':', count((new ReflectionClass($class))->getMethods()), ':', count(get_class_methods($class)), "\n";
}
foreach ((new ReflectionProperty(MetadataContract::class, 'x'))->getHooks() as $kind => $hook) {
    echo $kind, ':', $hook->getNumberOfParameters(), ':', $hook->getNumberOfRequiredParameters(), ':', $hook->getReturnType(), "\n";
    foreach ($hook->getParameters() as $param) echo $param->getName(), ':', $param->getType(), ':', (int)$param->isOptional(), "\n";
}
$o = new MetadataBacked;
echo $o->x, "\n";
$o->x = 8;
echo $o->x, "\n";
