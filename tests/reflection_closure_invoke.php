<?php
// a closure's __invoke reflects the closure's signature, Closure's own
// __invoke runs the closure it is given; getClosure, prototypes, getClass

class Base {
    function greet($name) { return "base $name"; }
    static function make() { return static::class; }
}
interface Greets { function greet($name); }
class Child extends Base implements Greets {
    public $bar = 42;
    function greet($name) { return "child $name"; }
    function useSelf(self $s, parent $p) {}
}

$closure = function (int $a, $b = 0): string { return "$a $b"; };
$m = new ReflectionMethod($closure, '__invoke');
var_dump($m->name, $m->class, $m->getNumberOfParameters(), $m->getNumberOfRequiredParameters());
var_dump($m->invoke($closure, 1, 2), $m->invokeArgs($closure, ['b' => 3, 'a' => 4]));
echo $m;
$params = $m->getParameters();
var_dump(get_class($params[0]->getDeclaringFunction()), $params[0]->getDeclaringFunction()->name);
$rp = new ReflectionParameter([$closure, '__invoke'], 'b');
var_dump($rp->isOptional(), $rp->getDeclaringFunction()->name);
var_dump((new ReflectionParameter($closure, 0))->getName());

$generic = (new ReflectionClass('Closure'))->getMethod('__invoke');
var_dump((new ReflectionClass('Closure'))->hasMethod('__invoke'), $generic->invoke(fn($x) => $x * 2, 21));
$names = array_map(fn($m) => $m->name, (new ReflectionObject($closure))->getMethods());
var_dump(end($names));

var_dump((new ReflectionMethod('Child', 'greet'))->getPrototype()->class);
var_dump((new ReflectionMethod('Child', 'greet'))->hasPrototype(), (new ReflectionMethod('Base', 'make'))->hasPrototype());
try {
    (new ReflectionMethod('Base', 'make'))->getPrototype();
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}

$f = (new ReflectionFunction('strtoupper'))->getClosure();
var_dump($f('abc'));
$g = (new ReflectionMethod('Child', 'greet'))->getClosure(new Child);
var_dump($g('x'), (new ReflectionFunction($g))->getClosureThis()->bar);
$h = (new ReflectionMethod('Child', 'make'))->getClosure();
var_dump($h());
try {
    (new ReflectionMethod('Child', 'greet'))->getClosure();
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    (new ReflectionMethod('Child', 'greet'))->getClosure(new stdClass);
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
var_dump((new ReflectionFunction(static function () {}))->isStatic(), (new ReflectionFunction(function () {}))->isStatic());

$u = 1;
$withUse = function () use ($u) { static $s = 5; };
var_dump((new ReflectionFunction($withUse))->getClosureUsedVariables(), (new ReflectionFunction($withUse))->getStaticVariables());

$p = new ReflectionMethod('Child', 'useSelf');
foreach ($p->getParameters() as $param) {
    var_dump(@$param->getClass()->name);
}
try {
    @(new ReflectionParameter(function (self $x) {}, 0))->getClass();
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
