<?php
$outer = function () {
    $x = 10;
    return function () use ($x) {
        return $x;
    };
};
$inner = $outer();
echo $inner(), "\n";

$a = 1; $b = 2; $c = 3;
$f = function () use ($a, $b, $c) {
    return $a + $b + $c;
};
echo $f(), "\n";

$x = 10;
$mk_inner = function () use ($x) {
    return function () use ($x) {
        return $x;
    };
};
$inner = $mk_inner();
$x = 99;
echo $inner(), "\n";

$ref = 0;
$mk = function () use (&$ref) {
    return function () use (&$ref) {
        return $ref;
    };
};
$f = $mk();
$ref = 100;
echo $f(), "\n";

$by_val = 1;
$by_ref = 2;
$f = function () use ($by_val, &$by_ref) {
    return "$by_val/$by_ref";
};
$by_val = 99;
$by_ref = 99;
echo $f(), "\n";

$accumulator = function () {
    $values = [];
    return function ($v) use (&$values) {
        $values[] = $v;
        return $values;
    };
};
$f = $accumulator();
print_r($f("a"));
print_r($f("b"));
print_r($f("c"));

$x = 5;
$arr1 = fn() => $x;
$arr2 = function () use ($x) { return $x; };
$x = 99;
echo $arr1(), "/", $arr2(), "\n";

$multiplier = 10;
$mapper = fn($x) => $x * $multiplier;
print_r(array_map($mapper, [1, 2, 3]));

$base = 100;
$f = fn() => fn() => $base;
echo $f()(), "\n";

$x = 10;
$f = fn() => fn() => fn() => $x;
echo $f()()(), "\n";

$x = 1;
$arrow = fn() => $x;
$x = 5;
echo $arrow(), "\n"; // 1 (captured at definition)

$x = 1;
$cl = function () use ($x) { return $x; };
$x = 5;
echo $cl(), "\n"; // 1

$x = 1;
$cl = function () use (&$x) { return $x; };
$x = 5;
echo $cl(), "\n"; // 5

class Box {
    public int $val = 10;
    public function makeMapper(): callable {
        $multiplier = 5;
        return fn($x) => $x * $multiplier * $this->val;
    }
}
print_r(array_map((new Box)->makeMapper(), [1, 2, 3]));

$counter1 = 0;
$counter2 = 0;
$inc1 = function () use (&$counter1) { $counter1++; };
$inc2 = function () use (&$counter2) { $counter2++; };
$inc1(); $inc1(); $inc2();
echo "$counter1/$counter2\n";

$x = 1;
function noCap() {
    return isset($x) ? "yes" : "no";
}
echo noCap(), "\n";

$captured = "outer";
$f = function () use ($captured) {
    $captured = "inner";
    return $captured;
};
echo $f(), "\n";
echo $captured, "\n"; // outer (by-value preserved)

$shared = [];
$f = function ($v) use (&$shared) {
    $shared[] = $v;
};
$f("a"); $f("b"); $f("c");
print_r($shared);

class Counter {
    public int $n = 0;
    public function makeInc(): callable {
        return function () { $this->n++; return $this->n; };
    }
}
$c = new Counter;
$inc = $c->makeInc();
echo $inc(), " ", $inc(), " ", $inc(), "\n";
echo $c->n, "\n";

$values = [10, 20, 30];
$readers = array_map(fn($i) => fn() => $values[$i], [0, 1, 2]);
foreach ($readers as $r) echo $r(), " ";
echo "\n";

$values = [];
for ($i = 0; $i < 3; $i++) {
    $values[] = function () use ($i) { return $i; };
}
foreach ($values as $f) echo $f(), " ";
echo "\n";

$base = 5;
$mod = 2;
$f = function ($x) use ($base, $mod) {
    return ($x + $base) * $mod;
};
echo $f(3), "\n";

$prefix = "[";
$suffix = "]";
$wrap = function ($s) use ($prefix, $suffix) {
    return $prefix . $s . $suffix;
};
echo $wrap("hi"), "\n";

$a = $b = $c = 0;
$add = function ($x, $y, $z) use (&$a, &$b, &$c) {
    $a += $x; $b += $y; $c += $z;
};
$add(1, 2, 3);
$add(10, 20, 30);
echo "$a/$b/$c\n";
