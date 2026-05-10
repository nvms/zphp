<?php
// Closure::fromCallable on methods
class Calc {
    public function add(int $a, int $b): int { return $a + $b; }
    public static function mul(int $a, int $b): int { return $a * $b; }
}

$cb = Closure::fromCallable([new Calc, 'add']);
echo $cb(3, 4), "\n";

$cb = Closure::fromCallable([Calc::class, 'mul']);
echo $cb(5, 6), "\n";

$cb = Closure::fromCallable('Calc::mul');
echo $cb(7, 8), "\n";

// Closure::fromCallable on string function
$cb = Closure::fromCallable('strlen');
echo $cb("hello"), "\n";

// Closure first-class
$cb = strlen(...);
echo $cb("world"), "\n";

class Foo { public function bar(int $x): int { return $x * 10; } public static function baz(int $x): int { return $x + 100; } }
$f = new Foo;
$cb = $f->bar(...);
echo $cb(5), "\n";

$cb = Foo::baz(...);
echo $cb(7), "\n";

// Reflection on closure
$cl = function (int $a, int $b = 10): bool { return $a > $b; };
$rf = new ReflectionFunction($cl);
echo $rf->getNumberOfParameters(), "\n";
foreach ($rf->getParameters() as $p) {
    echo $p->getName(), ":", $p->isOptional() ? "opt" : "req", "\n";
}

// Closure with captured vars
$x = 5;
$y = "hi";
$cl = function () use ($x, $y) { return "$x:$y"; };
$rf = new ReflectionFunction($cl);
$used = $rf->getClosureUsedVariables();
print_r($used);

// arrow function auto-captures - zphp captures more than PHP (architectural)
$mult = 3;
$fn = fn($a) => $a * $mult;
echo $fn(4), "\n";

// generator arrow function attempt - PHP doesn't allow yield in fn
// (compile error in PHP) - skipped here

// array_walk_recursive on iterators - PHP requires array (not iterable)
$src = new ArrayIterator([1, 2, 3]);
try {
    array_walk_recursive($src, function (&$v) { $v *= 10; });
    echo "no err\n";
} catch (\TypeError $e) { echo "te:array_walk_recursive\n"; }

// sort stability with arrays as values
$arr = [
    ["g" => 1, "id" => "a"],
    ["g" => 2, "id" => "b"],
    ["g" => 1, "id" => "c"],
    ["g" => 2, "id" => "d"],
    ["g" => 1, "id" => "e"],
];
usort($arr, fn($x, $y) => $x["g"] <=> $y["g"]);
foreach ($arr as $e) echo $e["id"];
echo "\n"; // ace bd (stable)

// SORT_FLAG_CASE on numeric strings
$arr = ["2", "10", "1", "B", "a"];
sort($arr, SORT_NATURAL | SORT_FLAG_CASE);
print_r($arr);

// usort with arrays of arrays
$arr = [[1, 2], [1, 1], [0, 5], [1, 3]];
usort($arr, fn($a, $b) => $a[0] <=> $b[0] ?: $a[1] <=> $b[1]);
print_r($arr);

// array_search with strict on objects
$o1 = new stdClass; $o1->v = 1;
$o2 = new stdClass; $o2->v = 1;
$arr = [$o1, $o2, "hello"];
var_dump(array_search($o1, $arr, true));
var_dump(array_search(new stdClass, $arr, true)); // false
var_dump(array_search($o1, $arr, false)); // 0 (loose: matches both objects equal)

// in_array with closure (no, in_array doesn't take callable)
// array_filter with key and closure
$arr = ["a" => 1, "b" => 2, "c" => 3];
$r = array_filter($arr, fn($v, $k) => $k !== "b", ARRAY_FILTER_USE_BOTH);
print_r($r);

$r = array_filter($arr, fn($k) => strlen($k) === 1, ARRAY_FILTER_USE_KEY);
print_r($r);

// array_walk with extra args
$arr = [1, 2, 3];
array_walk($arr, function (&$v, $k, $factor) { $v = $v * $factor + $k; }, 10);
print_r($arr);

// var_dump object id is implementation-specific (skipped)

// closure return type
$cl = function (): array { return [1, 2]; };
$rf = new ReflectionFunction($cl);
echo $rf->hasReturnType() ? "y" : "n", ":", $rf->getReturnType(), "\n";

// closure with callable type hint
$cl = function (callable $cb): mixed { return $cb(5); };
echo $cl(fn($n) => $n * 2), "\n";

// nested closure with this
class Container {
    private int $val = 42;
    public function build(): callable {
        return function () {
            return function () { return $this->val; };
        };
    }
}
$outer = (new Container)->build();
$inner = $outer();
echo $inner(), "\n"; // 42
