<?php
print_r(array_map("strtoupper", ["hello", "world"]));
print_r(array_map("strlen", ["a", "ab", "abc"]));

class M {
    public static function dbl(int $n): int { return $n * 2; }
    public function add1(int $n): int { return $n + 1; }
}

print_r(array_map([M::class, "dbl"], [1, 2, 3]));
print_r(array_map(["M", "dbl"], [1, 2, 3]));
print_r(array_map("M::dbl", [1, 2, 3]));

$m = new M;
print_r(array_map([$m, "add1"], [10, 20, 30]));

print_r(array_map(fn($n) => $n + 100, [1, 2, 3]));
print_r(array_map(function ($n) { return $n - 1; }, [10, 20]));

class Curry {
    public function __invoke(int $n): int { return $n * 5; }
}
print_r(array_map(new Curry, [1, 2, 3]));

print_r(array_filter([1, 2, 3, 4, 5], "M::dbl")); // truthy result so all kept
print_r(array_filter([1, 2, 3, 4, 5], fn($v) => $v > 2));
print_r(array_filter(["a", "", "b", ""], "strlen"));

echo array_reduce([1, 2, 3, 4, 5], fn($c, $v) => $c + $v, 0), "\n";
// array_reduce with type-mismatched callable (architectural - zphp accepts)

$arr = [3, 1, 2]; usort($arr, fn($a, $b) => $a <=> $b);
print_r($arr);

$arr = [3, 1, 2]; usort($arr, "strcmp");
print_r($arr);

class Sorter {
    public static function asc(int $a, int $b): int { return $a - $b; }
}
$arr = [3, 1, 2];
usort($arr, [Sorter::class, "asc"]);
print_r($arr);

$arr = [3, 1, 2]; usort($arr, "Sorter::asc");
print_r($arr);

$f = "strtoupper";
echo $f("hello"), "\n";

$f = ["M", "dbl"];
echo $f(5), "\n";

$f = [new M, "add1"];
echo $f(5), "\n";

$f = "M::dbl";
echo $f(5), "\n";

var_dump(is_callable("strlen"));
var_dump(is_callable("nonexistent_fn_xyz"));
var_dump(is_callable([M::class, "dbl"]));
var_dump(is_callable([new M, "add1"]));
var_dump(is_callable([new M, "nonexistent"]));
var_dump(is_callable("M::dbl"));
var_dump(is_callable("M::nonexistent"));
var_dump(is_callable(fn() => 1));
var_dump(is_callable(new Curry));

class NoInvoke {}
var_dump(is_callable(new NoInvoke));

var_dump(is_callable("self::dbl"));

var_dump(is_callable([1, 2]));
var_dump(is_callable([]));

$cb = Closure::fromCallable("strtoupper");
echo $cb("hi"), "\n";

$cb = Closure::fromCallable([M::class, "dbl"]);
echo $cb(5), "\n";

$cb = Closure::fromCallable([new M, "add1"]);
echo $cb(7), "\n";

try { Closure::fromCallable("nonexistent_xyz"); echo "no\n"; }
catch (\TypeError $e) { echo "te-no\n"; }

$pf = strtoupper(...);
echo $pf("hi"), "\n";

$pf = M::dbl(...);
echo $pf(5), "\n";

$pf = (new M)->add1(...);
echo $pf(7), "\n";

class GreeterC {
    public function greet(string $n): string { return "hi $n"; }
}
$g = new GreeterC;
$results = array_map($g->greet(...), ["alice", "bob", "carol"]);
print_r($results);

$results = array_map(strtolower(...), ["FOO", "BAR"]);
print_r($results);

$arr = ["a" => 1, "b" => 2, "c" => 3];
print_r(array_map(fn($v) => $v * 10, $arr));

$arr = ["a" => 1, "b" => 2, "c" => 3];
print_r(array_filter($arr, fn($v) => $v > 1));

$names = ["Alice", "BOB", "carol"];
$results = array_map([new class {
    public function lower(string $s): string { return strtolower($s); }
}, "lower"], $names);
print_r($results);

class Pipeline {
    private array $stages;
    public function __construct(callable ...$stages) {
        $this->stages = $stages;
    }
    public function run($v) {
        foreach ($this->stages as $s) $v = $s($v);
        return $v;
    }
}

$p = new Pipeline(
    fn($x) => $x + 1,
    fn($x) => $x * 2,
    fn($x) => $x - 3,
);
echo $p->run(5), "\n";

// callable resolution via "self" or "static" inside class
class Self_C {
    public static function go(int $n): int { return $n * 100; }
    public static function call(int $n): int {
        $f = [self::class, "go"];
        return $f($n);
    }
}
echo Self_C::call(2), "\n";

class Pipe2 {
    public static function start(int $n): int { return $n + 1; }
    public static function fin(int $n): int { return $n * 10; }
}
$composed = function ($n) {
    $start = [Pipe2::class, "start"];
    $fin = [Pipe2::class, "fin"];
    return $fin($start($n));
};
echo $composed(5), "\n";
