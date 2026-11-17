<?php
// getProperties lists static and instance properties in declaration order
class Ordered {
    public static $first = 1;
    public $a;
    protected static $second;
    private $b = 2;
    public int $c = 3;
    public static ?string $third = null;
    public $hooked { get => 4; }
    private static $fourth = [];
}
class Child extends Ordered {
    public static $own;
    public $d;
}
function names(array $props): string {
    return implode(', ', array_map(fn($p) => ($p->isStatic() ? 'static ' : '') . $p->class . '::' . $p->name, $props));
}
$r = new ReflectionClass('Ordered');
echo names($r->getProperties()), "\n";
echo names($r->getProperties(ReflectionProperty::IS_STATIC)), "\n";
echo names($r->getProperties(ReflectionProperty::IS_PUBLIC)), "\n";
echo names($r->getProperties(ReflectionProperty::IS_PRIVATE | ReflectionProperty::IS_STATIC)), "\n";
echo names((new ReflectionClass('Child'))->getProperties()), "\n";
echo implode(', ', array_keys($r->getStaticProperties())), "\n";
echo implode(', ', array_keys($r->getDefaultProperties())), "\n";
