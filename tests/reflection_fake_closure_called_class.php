<?php
// a closure made from a static method callable is called through the class
// it was made from

class A {
    public static function __callStatic($name, $args) { echo static::class, "::$name\n"; }
    public function __call($name, $args) { echo static::class, "->$name\n"; }
    public static function b() { echo static::class, "::b\n"; }
    public function c() { echo static::class, "->c\n"; }
}
class B extends A {}

$callables = [['B', 'b'], [new B, 'c'], ['B', 'd'], [new B, 'e'], ['A', 'b'], 'B::b', 'A::d'];
foreach ($callables as $c) {
    $d = Closure::fromCallable($c);
    $r = new ReflectionFunction($d);
    echo $r->getClosureCalledClass()?->getName() ?? 'none', ": ";
    $d();
}

$f = B::b(...);
echo (new ReflectionFunction($f))->getClosureCalledClass()->getName(), "\n";
$g = strlen(...);
var_dump((new ReflectionFunction($g))->getClosureCalledClass());
