<?php
// a static property's default is what it was declared with, whatever it
// holds now

class Statics {
    public static $staticVar = 1;
    public static $list = [1, 2];
    protected static ?int $typed = null;
    public static $noDefault;
    public $instance = 'i';
}
class Child extends Statics {
    public static $own = 'own';
}
trait T {
    public static $fromTrait = 't';
}
class UsesTrait {
    use T;
}

Statics::$staticVar = 2;
Statics::$list[] = 3;
Statics::$noDefault = 'set';
Child::$own = 'changed';
UsesTrait::$fromTrait = 'changed';

foreach (['staticVar', 'list', 'typed', 'noDefault'] as $name) {
    $prop = new ReflectionProperty(Statics::class, $name);
    var_dump($prop->hasDefaultValue(), $prop->getDefaultValue());
}
var_dump((new ReflectionProperty(Child::class, 'staticVar'))->getDefaultValue());
var_dump((new ReflectionProperty(Child::class, 'own'))->getDefaultValue());
var_dump((new ReflectionProperty(UsesTrait::class, 'fromTrait'))->getDefaultValue());
var_dump((new ReflectionClass(Statics::class))->getDefaultProperties());
var_dump(Statics::$staticVar, Statics::$list);
$props = (new ReflectionClass(Child::class))->getProperties(ReflectionProperty::IS_STATIC);
usort($props, fn ($a, $b) => strcmp($a->getName(), $b->getName()));
foreach ($props as $p) {
    echo $p->getName(), ": ";
    var_dump($p->getDefaultValue());
}
echo new ReflectionProperty(Statics::class, 'staticVar');
