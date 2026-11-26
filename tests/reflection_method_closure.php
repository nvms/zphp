<?php
// a closure of a method reflects as that method: its name alone, the
// class declaring it as scope, the class called through, its attributes

#[Attribute]
class Marker {}

class Base {
    #[Deprecated("use other")]
    public function __invoke($a) {}

    #[Marker]
    public function run(int $a, $b = 1) {}

    #[Marker]
    public static function make(string ...$parts) {}
}
class Child extends Base {}

$obj = new Child;
$closures = [
    'invokable' => Closure::fromCallable($obj),
    'method array' => Closure::fromCallable([$obj, 'run']),
    'first-class method' => $obj->run(...),
    'first-class static' => Child::make(...),
    'static string' => Closure::fromCallable('Child::make'),
];
foreach ($closures as $label => $closure) {
    echo "-- $label\n";
    $r = new ReflectionFunction($closure);
    var_dump($r->name, $r->getName(), $r->getShortName(), $r->getNamespaceName(), $r->inNamespace());
    var_dump($r->getClosureScopeClass()?->name, $r->getClosureCalledClass()?->name);
    var_dump($r->isStatic(), $r->isClosure(), $r->isDeprecated(), $r->getNumberOfParameters());
    var_dump(array_map(fn($a) => $a->getName(), $r->getAttributes()));
    echo $r;

    $m = new ReflectionMethod($closure, '__invoke');
    var_dump($m->name, $m->class, $m->getNumberOfParameters(), $m->isDeprecated());
    var_dump(array_map(fn($a) => $a->getName(), $m->getAttributes()));
}

// the closure a closure's __invoke(...) makes is the closure, so it
// reflects the same
$inner = Closure::fromCallable($obj);
$m = new ReflectionMethod($inner->__invoke(...), '__invoke');
var_dump($m->isDeprecated(), count($m->getAttributes()));

$plain = #[Marker] function (int $x) {};
$m = new ReflectionMethod($plain, '__invoke');
var_dump(array_map(fn($a) => $a->getName(), $m->getAttributes()), $m->isDeprecated());
