<?php
$factorial = function ($n) use (&$factorial) {
    return $n <= 1 ? 1 : $n * $factorial($n - 1);
};
echo $factorial(5), "\n";
echo $factorial(10), "\n";
echo $factorial(0), "\n";

$fib = function ($n) use (&$fib) {
    return $n < 2 ? $n : $fib($n - 1) + $fib($n - 2);
};
echo $fib(10), "\n";

$ackermann = function ($m, $n) use (&$ackermann) {
    if ($m === 0) return $n + 1;
    if ($n === 0) return $ackermann($m - 1, 1);
    return $ackermann($m - 1, $ackermann($m, $n - 1));
};
echo $ackermann(2, 3), "\n";

$reduce_fn = function (array $arr, callable $fn, $init) {
    return array_reduce($arr, $fn, $init);
};
echo $reduce_fn([1, 2, 3, 4, 5], fn($c, $v) => $c + $v, 0), "\n";

$pipeline = array_reduce(
    [
        fn($x) => $x + 1,
        fn($x) => $x * 2,
        fn($x) => $x - 3,
    ],
    fn($carry, $f) => fn($x) => $f($carry($x)),
    fn($x) => $x,
);
echo $pipeline(5), "\n";

$compose = fn(...$fns) => array_reduce(
    array_reverse($fns),
    fn($carry, $f) => fn($x) => $carry($f($x)),
    fn($x) => $x,
);

$f = $compose(
    fn($x) => $x * 2,
    fn($x) => $x + 1,
);
echo $f(5), "\n";

$add = fn($a) => fn($b) => $a + $b;
$add5 = $add(5);
echo $add5(3), "\n";
echo $add5(7), "\n";

$add3 = fn($a) => fn($b) => fn($c) => $a + $b + $c;
echo $add3(1)(2)(3), "\n";

$curry = function (callable $fn, int $arity) use (&$curry) {
    return function (...$args) use ($fn, $arity, &$curry) {
        if (count($args) >= $arity) {
            return $fn(...array_slice($args, 0, $arity));
        }
        return $curry(fn(...$rest) => $fn(...$args, ...$rest), $arity - count($args));
    };
};

$add4 = $curry(fn($a, $b, $c, $d) => $a + $b + $c + $d, 4);
echo $add4(1, 2, 3, 4), "\n";
echo $add4(1)(2)(3)(4), "\n";
echo $add4(1, 2)(3, 4), "\n";

class Container {
    public function __construct(public int $val) {}
}

$cl = function () { return $this->val; };
$bound = Closure::bind($cl, new Container(42), Container::class);
echo $bound(), "\n";

$bound2 = Closure::bind($cl, new Container(100), Container::class);
echo $bound2(), "\n";

$bindable = function ($n) { return $this->val * $n; };
$first = Closure::bind($bindable, new Container(5), Container::class);
$second = Closure::bind($bindable, new Container(10), Container::class);
echo $first(3), " ", $second(3), "\n";

class C {
    public int $val = 99;
}
$cl = function ($x) { return $this->val + $x; };
echo $cl->call(new C, 1), "\n";

class CounterC { public int $n = 0; }
$inc = function (int $by) { $this->n += $by; return $this->n; };
$c = new CounterC;
$bound = $inc->bindTo($c, CounterC::class);
echo $bound(5), "\n";
echo $bound(3), "\n";
echo $c->n, "\n";

$fns = [];
for ($i = 0; $i < 3; $i++) {
    $fns[] = fn() => $i;
}
foreach ($fns as $f) echo $f(), " ";
echo "\n";

$fns = [];
for ($i = 0; $i < 3; $i++) {
    $local = $i;
    $fns[] = function () use ($local) { return $local; };
}
foreach ($fns as $f) echo $f(), " ";
echo "\n";

$nodes = [
    [1, [2, [3, [4]]]],
];
$flatten = function ($x) use (&$flatten) {
    if (!is_array($x)) return [$x];
    $out = [];
    foreach ($x as $v) {
        $out = array_merge($out, $flatten($v));
    }
    return $out;
};
print_r($flatten($nodes));

$applyAll = fn(array $fns, $val) => array_reduce($fns, fn($c, $f) => $f($c), $val);
echo $applyAll([
    fn($x) => $x * 2,
    fn($x) => $x + 1,
    fn($x) => $x - 3,
], 10), "\n";

$mapper = fn(callable $f) => fn(array $a) => array_map($f, $a);
$dbl = $mapper(fn($x) => $x * 2);
print_r($dbl([1, 2, 3]));

$once = function (callable $f): callable {
    $called = false;
    $result = null;
    return function (...$args) use ($f, &$called, &$result) {
        if (!$called) {
            $result = $f(...$args);
            $called = true;
        }
        return $result;
    };
};
$counter = 0;
$o = $once(function () use (&$counter) { $counter++; return "first"; });
echo $o(), " ", $o(), " ", $o(), " counter=$counter\n";

$memo = function (callable $f): callable {
    $cache = [];
    return function (...$args) use ($f, &$cache) {
        $key = serialize($args);
        if (!isset($cache[$key])) $cache[$key] = $f(...$args);
        return $cache[$key];
    };
};

$slow = function ($x) {
    return $x * $x;
};
$mslow = $memo($slow);
echo $mslow(5), " ", $mslow(5), " ", $mslow(7), "\n";
