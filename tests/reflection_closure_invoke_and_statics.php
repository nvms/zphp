<?php
// ReflectionMethod of a closure's __invoke reflects the closure's function,
// a Closure made from a callable included, and invoking it with a closure of
// another function fails; static variables show null until a declaration
// that reads a constant at run time has run; getClass() finds the one class
// of a union type

$c1 = function ($foo, $bar) { echo "c1: $foo $bar\n"; };
$c2 = function ($bar, $foo) { echo "c2: $foo $bar\n"; };
$m = new ReflectionMethod($c1, '__invoke');
$m->invokeArgs($c1, ['foo' => 'F', 'bar' => 'B']);
foreach ([fn() => $m->invokeArgs($c2, ['foo' => 'F', 'bar' => 'B']), fn() => $m->invoke($c2, 1, 2)] as $call) {
    try {
        $call();
        echo "no exception\n";
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
}
$closures = [];
for ($i = 0; $i < 3; $i++) {
    $closures[] = function () use ($i) { return $i; };
}
$m2 = new ReflectionMethod($closures[0], '__invoke');
foreach ($closures as $closure) var_dump($m2->invoke($closure));

function my_func($x) { return "my_func: $x"; }
function other_func($x) { return "other_func: $x"; }
$m3 = new ReflectionMethod(my_func(...), '__invoke');
var_dump($m3->invoke(my_func(...), 'a'), $m3->getNumberOfParameters(), $m3->getParameters()[0]->getName());
$vd = var_dump(...);
$m4 = new ReflectionMethod($vd, '__invoke');
$m4->invoke(clone $vd, 'internal ok');
var_dump($m4->getNumberOfParameters(), $m4->getNumberOfRequiredParameters());
foreach ([[$m3, other_func(...)], [$m4, print_r(...)], [$m4, $c1], [$m, $vd]] as [$rm, $target]) {
    try {
        $rm->invoke($target, 'x', 'y');
        echo "no exception\n";
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
}
$p = (new ReflectionMethod((new ReflectionFunction('iterator_to_array'))->getClosure(), '__invoke'))->getParameters()[0];
var_dump((string) $p->getType(), $p->getName());

$closure = function () {
    static $var = CONST_REF;
    static $lit = [1, 'a' => 2];
    static $n = 5;
    static $arr = [CONST_REF];
    static $max = PHP_INT_MAX;
};
var_dump((new ReflectionFunction($closure))->getStaticVariables());
try {
    $closure();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
const CONST_REF = 'foo';
$closure();
var_dump((new ReflectionFunction($closure))->getStaticVariables());

class Test {
    const A = 0;
    public function func() {
        static $a = [self::A => 'a'];
        static $b = [Test::A => 'b'];
        static $c = OTHER;
    }
}
const OTHER = 1;
var_dump((new ReflectionMethod('Test', 'func'))->getStaticVariables());

interface I {}
interface J {}
function f(iterable $a, Traversable|array $b, ?I $c, I|int|null $d, I|J $e, I&J $f, int $g, $h, (I&J)|null $i) {}
foreach ((new ReflectionFunction('f'))->getParameters() as $param) {
    $class = @$param->getClass();
    echo $param->getName(), ": ", $class ? $class->getName() : "null", "\n";
}
