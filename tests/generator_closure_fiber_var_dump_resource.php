<?php
function gen() { yield 1; yield 2; yield 3; }
$g = gen();
echo get_class($g), "\n";
echo $g instanceof Generator ? "y" : "n", "\n";
echo $g instanceof Iterator ? "y" : "n", "\n";
echo $g instanceof Traversable ? "y" : "n", "\n";

echo $g->current(), "\n";
$g->next();
echo $g->current(), "\n";

$cl = function (int $x): int { return $x * 2; };
echo get_class($cl), "\n";
echo $cl instanceof Closure ? "y" : "n", "\n";
echo $cl(5), "\n";

$arrow = fn(int $x) => $x + 100;
echo get_class($arrow), "\n";
echo $arrow(5), "\n";

$static = static function (): int { return 42; };
echo $static(), "\n";

$invoked = (fn() => "hello")();
echo $invoked, "\n";

if (class_exists("Fiber")) {
    $f = new Fiber(function () {
        Fiber::suspend("paused");
        return "done";
    });
    echo get_class($f), "\n";
    echo $f instanceof Fiber ? "y" : "n", "\n";
    $r = $f->start();
    echo $r, "\n";
    $r = $f->resume();
    echo $r, "\n";
}

function counter() {
    for ($i = 1; $i <= 3; $i++) yield $i;
}
foreach (counter() as $v) echo $v, " ";
echo "\n";

$g = counter();
echo "before:", $g->valid() ? "y" : "n", "\n";
echo $g->current(), "\n";
$g->next();
echo $g->current(), "\n";

class Container {
    public Closure $cb;
    public function __construct(Closure $c) { $this->cb = $c; }
    public function run(int $x): int { return ($this->cb)($x); }
}

$c = new Container(fn($x) => $x * 3);
echo $c->run(5), "\n";

$wrapper = function (string $name): callable {
    return fn() => "hello, " . $name;
};
$greet = $wrapper("alice");
echo $greet(), "\n";

$composed = fn($x) => (fn($y) => $y * 2)($x + 1);
echo $composed(5), "\n";

class WithGen {
    public function evens(): Generator {
        for ($i = 0; $i < 5; $i++) yield $i * 2;
    }
}

foreach ((new WithGen)->evens() as $v) echo $v, " ";
echo "\n";

function delegating() {
    yield 1;
    yield from [2, 3, 4];
    yield 5;
}
foreach (delegating() as $v) echo $v, " ";
echo "\n";

function infinite() {
    $i = 0;
    while (true) yield $i++;
}
$gen = infinite();
$first_5 = [];
foreach ($gen as $v) {
    $first_5[] = $v;
    if (count($first_5) >= 5) break;
}
print_r($first_5);

$pipe = function (...$fns) {
    return fn($x) => array_reduce($fns, fn($acc, $fn) => $fn($acc), $x);
};

$add1 = fn($x) => $x + 1;
$mul2 = fn($x) => $x * 2;
$sub3 = fn($x) => $x - 3;
$chained = $pipe($add1, $mul2, $sub3);
echo $chained(10), "\n";

function genWithReturn(): Generator {
    yield 1;
    yield 2;
    return "completed";
}

$g = genWithReturn();
foreach ($g as $v) echo $v, " ";
echo "\n";
echo $g->getReturn(), "\n";

$path = sys_get_temp_dir() . "/_zphp_dump_probe.txt";
file_put_contents($path, "test");
$h = fopen($path, "r");
echo is_resource($h) || is_object($h) ? "y" : "n", "\n";
echo get_resource_type($h), "\n";
fclose($h);
unlink($path);

echo (function () { return "iife"; })(), "\n";

$factory = function ($x) {
    return function () use ($x) { return $x; };
};
$five = $factory(5);
$ten = $factory(10);
echo $five() + $ten(), "\n";

class Adder {
    public function __construct(public int $base) {}
    public function add(int $x): int { return $this->base + $x; }
}
$a = new Adder(100);
$add = Closure::fromCallable([$a, "add"]);
echo $add(5), "\n";

$boundClosure = Closure::bind(fn() => 99, null);
echo $boundClosure(), "\n";

$lazy = fn() => fn() => "deferred";
echo $lazy()(), "\n";
