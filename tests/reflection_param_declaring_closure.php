<?php
// a parameter of a closure with a class scope is declared by a
// ReflectionMethod of that class named as the closure; without one, by a
// ReflectionFunction
class A {
    function make() { return function ($x) {}; }
}
class B extends A {}

$plain = function ($a, $b = 0) {};
$bound = $plain->bindTo(new B, B::class);
foreach ([$plain, $bound, (new A)->make(), static fn ($y) => $y] as $closure) {
    $param = (new ReflectionFunction($closure))->getParameters()[0];
    $decl = $param->getDeclaringFunction();
    echo get_class($decl), ' ', str_contains($decl->getName(), '{closure:') ? 'closure' : $decl->getName();
    if ($decl instanceof ReflectionMethod) echo ' of ', $decl->class;
    echo "\n";
}
