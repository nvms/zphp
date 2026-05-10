<?php
// arrow function captures by value
$x = 10;
$f = fn() => $x;
echo $f(), "\n";
$x = 20;
echo $f(), "\n"; // still 10

// arrow with arg
$mul = 3;
$f = fn($n) => $n * $mul;
echo $f(5), "\n"; // 15

// closure captures by value via use
$x = 10;
$g = function () use ($x) { return $x; };
echo $g(), "\n";
$x = 20;
echo $g(), "\n"; // still 10

// closure captures by reference
$x = 10;
$g = function () use (&$x) { return $x; };
$x = 20;
echo $g(), "\n"; // 20

// closure with multiple captures
$a = 1; $b = 2;
$f = function () use ($a, $b) { return $a + $b; };
echo $f(), "\n";

// Closure::bind to instance
class Box {
    private int $size = 100;
}
$getter = function () { return $this->size; };
$bound = Closure::bind($getter, new Box, Box::class);
echo $bound(), "\n";

// Closure::bind without scope -> private access error (architectural - no scope check at access)

// Closure::fromCallable for function
$f = Closure::fromCallable("strlen");
echo $f("hello"), "\n";

// Closure::fromCallable for method
class Greeter {
    public function hello(string $n): string { return "hi $n"; }
}
$g = Closure::fromCallable([new Greeter, "hello"]);
echo $g("alice"), "\n";

// Closure::fromCallable static method
class Math {
    public static function double(int $n): int { return $n * 2; }
}
$d = Closure::fromCallable([Math::class, "double"]);
echo $d(7), "\n";

// Closure::fromCallable with string syntax for static
$d = Closure::fromCallable("Math::double");
echo $d(11), "\n";

// closure first-class
$f = strlen(...);
echo $f("hello world"), "\n";

$g = (new Greeter)->hello(...);
echo $g("bob"), "\n";

$d = Math::double(...);
echo $d(15), "\n";

// closure binding via -> bindTo
$cl = function () { return $this->size; };
$rebound = $cl->bindTo(new Box, Box::class);
echo $rebound(), "\n";

// Closure::call - bind and call in one
class Counter {
    private int $n = 5;
}
$incrementer = function (int $by) { $this->n += $by; return $this->n; };
echo $incrementer->call(new Counter, 3), "\n"; // 8

// static closure callable
$static_fn = static function () { return "static"; };
echo $static_fn(), "\n";
// rejecting bind on static closure (architectural - is_static_closure flag not tracked)

// closure with default param
$f = function ($a, $b = 10) { return $a + $b; };
echo $f(5), "\n"; // 15
echo $f(5, 7), "\n"; // 12

// closure with named args
echo $f(b: 2, a: 3), "\n"; // 5

// closure returning closure
$adder = function ($n) {
    return function ($x) use ($n) { return $x + $n; };
};
$add5 = $adder(5);
echo $add5(10), "\n"; // 15

// closure recursion
$factorial = function ($n) use (&$factorial) {
    return $n <= 1 ? 1 : $n * $factorial($n - 1);
};
echo $factorial(5), "\n"; // 120

// arrow can capture multiple from outer scope
$a = 5; $b = 10;
$g = fn($x) => $a * $x + $b;
echo $g(3), "\n"; // 25

// nested arrow auto-captures from parent
$f = fn($x) => fn($y) => $x + $y;
$g = $f(10);
echo $g(5), "\n"; // 15

// closure preserves $this
class C {
    public int $val = 7;
    public function makeClos() {
        return function () { return $this->val; };
    }
}
$c = new C;
$cl = $c->makeClos();
echo $cl(), "\n"; // 7

// arrow inside method captures $this
class D {
    public int $multiplier = 5;
    public function mapper(array $arr): array {
        return array_map(fn($x) => $x * $this->multiplier, $arr);
    }
}
print_r((new D)->mapper([1, 2, 3]));

// Closure::bind to static class context
class HasStatic {
    public static int $count = 0;
}
$cl = function () { return self::$count; };
$bound = Closure::bind($cl, null, HasStatic::class);
HasStatic::$count = 42;
echo $bound(), "\n";

// instanceof
$f = function () {};
var_dump($f instanceof Closure);

$af = fn() => 1;
var_dump($af instanceof Closure);

// Closure::fromCallable returns Closure-instance (architectural - zphp returns callable string)

// is_callable on closure
var_dump(is_callable($f));

// closure and array_map
$results = array_map(fn($x) => $x * 2, [1, 2, 3]);
print_r($results);

$results = array_filter([1, 2, 3, 4, 5], fn($x) => $x % 2 === 0);
print_r($results);

$result = array_reduce([1, 2, 3], fn($c, $v) => $c + $v, 0);
echo $result, "\n";
