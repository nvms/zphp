<?php
function greet($name) { return "hello, $name"; }

$f = Closure::fromCallable("greet");
echo $f("alice"), "\n";
echo $f("bob"), "\n";

$f = Closure::fromCallable("strtoupper");
echo $f("hello"), "\n";

class Foo {
    public static function bar(int $x): int { return $x * 2; }
    public function baz(int $x): int { return $x + 100; }
    private static function priv(int $x): int { return $x; }
}

$f = Closure::fromCallable(["Foo", "bar"]);
echo $f(5), "\n";
$f = Closure::fromCallable("Foo::bar");
echo $f(7), "\n";

$obj = new Foo;
$f = Closure::fromCallable([$obj, "baz"]);
echo $f(10), "\n";
$f = Closure::fromCallable([$obj, "bar"]);
echo $f(3), "\n";

class Inv {
    public function __invoke(int $x): int { return $x * 10; }
}
$inv = new Inv;
$f = Closure::fromCallable($inv);
echo $f(4), "\n";

$add = fn($a, $b) => $a + $b;
$f = Closure::fromCallable($add);
echo $f(2, 3), "\n";

try {
    Closure::fromCallable("does_not_exist");
    echo "no\n";
} catch (\TypeError $e) {
    echo "te\n";
}

$arr = ["Foo", "doesNotExist"];
try {
    $f = Closure::fromCallable($arr);
    echo "no\n";
} catch (\TypeError $e) {
    echo "te\n";
}

$f = strtoupper(...);
echo $f("hello world"), "\n";

$f = "greet"(...);
echo $f("carol"), "\n";

$f = Foo::bar(...);
echo $f(8), "\n";

$obj = new Foo;
$f = $obj->baz(...);
echo $f(50), "\n";

class Counter {
    private int $n = 0;
    public function inc(): int { return ++$this->n; }
    public function get(): int { return $this->n; }
}

$c = new Counter;
$inc = $c->inc(...);
$get = $c->get(...);
echo $inc(), " ", $inc(), " ", $inc(), "\n";
echo $get(), "\n";

$arr = [1, 2, 3];
$mapper = fn($x) => $x * 10;
print_r(array_map($mapper, $arr));
print_r(array_map(strtoupper(...), ["a", "b"]));

class Adder {
    private int $base;
    public function __construct(int $b) { $this->base = $b; }
    public function add(int $x): int { return $this->base + $x; }
}
$a = new Adder(100);
$add = $a->add(...);
echo $add(5), "\n";
print_r(array_map($add, [1, 2, 3]));

$cls = "Adder";
$obj = new $cls(50);
$f = [$obj, "add"];
echo call_user_func($f, 7), "\n";
echo $f(7), "\n";

class WithStatic {
    public static function ten(): int { return 10; }
}
$f = ["WithStatic", "ten"];
echo $f(), "\n";
echo call_user_func($f), "\n";

$cb = "strlen";
$f = $cb(...);
echo $f("hello"), "\n";
echo call_user_func($cb, "hello world"), "\n";
echo call_user_func_array("strpos", ["hello world", "wor"]), "\n";

$lambda = function ($x) { return $x ** 2; };
$f = Closure::fromCallable($lambda);
echo $f(5), "\n";
echo $f === $lambda ? "same" : "wrap", "\n";

$cb = ["Foo", "bar"];
echo is_callable($cb) ? "y" : "n", "\n";
echo is_callable("Foo::bar") ? "y" : "n", "\n";
echo is_callable("does_not_exist") ? "y" : "n", "\n";
echo is_callable(fn() => 1) ? "y" : "n", "\n";
echo is_callable(new Inv) ? "y" : "n", "\n";

$cb = ["Foo", "priv"];
echo is_callable($cb) ? "y" : "n", "\n";

class Caller {
    public static function call() {
        return is_callable([Foo::class, "priv"]) ? "y" : "n";
    }
}
