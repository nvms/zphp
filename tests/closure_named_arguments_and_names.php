<?php
// closures called with named arguments, the names php gives closures in
// is_callable() and errors, and Reflection's getClosure()
function pick(string $a1 = 'a1', string $a2 = 'a2', string $a3 = 'a3') {
    return "a1=$a1 a2=$a2 a3=$a3";
}
$closure = function (string $a1 = 'a1', string $a2 = 'a2', string $a3 = 'a3') {
    return "a1=$a1 a2=$a2 a3=$a3";
};
$fcc = pick(...);
echo $closure(a3: 'x'), "\n";
echo $closure('p', a3: 'y'), "\n";
echo $closure(...['a2' => 'z']), "\n";
echo $fcc(a2: 'w'), "\n";
echo $fcc(...['a3' => 'v']), "\n";
try {
    $closure(nope: 1);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

class Greeter {
    public function __invoke() {}
    public static function hello($name) { return "hello $name"; }
    public function hi($name) { return "hi $name"; }
}
function made() {
    return function ($required) {};
}
foreach ([made(), pick(...), (new Greeter)(...), Greeter::hello(...), (new Greeter)->hi(...), [made(), '__invoke']] as $callable) {
    is_callable($callable, false, $name);
    echo $name, "\n";
}
try {
    made()();
} catch (ArgumentCountError $e) {
    echo preg_replace('/ in .* on line \d+/', '', $e->getMessage()), "\n";
}

$method = new ReflectionMethod(Greeter::class, 'hello');
echo $method->getClosure()('world'), "\n";
$instance = new ReflectionMethod(Greeter::class, 'hi');
$hi = $instance->getClosure(new Greeter);
var_dump($hi instanceof Closure);
echo $hi('there'), "\n";
$fn = new ReflectionFunction('pick');
echo $fn->getClosure()(a1: 'reflected'), "\n";
$c = made();
var_dump((new ReflectionFunction($c))->getClosure() === $c);
