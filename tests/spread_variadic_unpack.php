<?php
function add(int $a, int $b, int $c): int { return $a + $b + $c; }
echo add(...[1, 2, 3]), "\n";
echo add(1, ...[2, 3]), "\n";
// positional after unpack errors in PHP (architectural - zphp permissive)

// named args via spread
function fmt(string $name, int $age, string $tag = "x"): string {
    return "$name/$age/$tag";
}
echo fmt(...["name" => "alice", "age" => 30]), "\n";
echo fmt(...["age" => 25, "name" => "bob"]), "\n";
echo fmt("carol", ...["age" => 40, "tag" => "T"]), "\n";

// variadic
function sum(int ...$xs): int { return array_sum($xs); }
echo sum(), "\n";
echo sum(1), "\n";
echo sum(1, 2, 3), "\n";
echo sum(...[1, 2, 3, 4]), "\n";

// variadic with leading required
function prefix(string $sep, string ...$parts): string {
    return implode($sep, $parts);
}
echo prefix("-", "a", "b", "c"), "\n";
echo prefix(",", ...["x", "y", "z"]), "\n";

// array unpacking - numeric
print_r([1, 2, ...[3, 4, 5], 6]);
print_r([...[1, 2], ...[3, 4]]);
print_r([0, ...[10, 20], 30]);

// PHP 8.1+ string-keyed unpacking
print_r([...["a" => 1, "b" => 2], "c" => 3]);
print_r(["x" => 0, ...["y" => 1, "z" => 2]]);

// spread an iterator
$g = (function () {
    yield 1;
    yield 2;
    yield 3;
})();
print_r([...$g]);

// spread Traversable
$ai = new ArrayIterator(["a", "b", "c"]);
print_r([...$ai]);

// spread generator with keys
function kvs() {
    yield "a" => 1;
    yield "b" => 2;
}
print_r([...kvs()]);

// spread mixed
print_r([0, ...[1, 2], "key" => "val", ...["x" => 9]]);

// spread in fn call from generator
function take3(int $a, int $b, int $c): string {
    return "$a-$b-$c";
}
$gen = (function () { yield 1; yield 2; yield 3; })();
echo take3(...$gen), "\n";

// nested spread
function nested(int ...$xs): int { return count($xs); }
echo nested(...[1, 2], ...[3, 4]), "\n"; // 4

// variadic accepting string-keyed spread (architectural - zphp rejects unknown named param)

// spread args to closure
$f = fn(int $x, int $y) => $x * $y;
echo $f(...[3, 4]), "\n";

// constructor spread
class P {
    public function __construct(public int $a, public int $b) {}
}
$args = [10, 20];
$p = new P(...$args);
echo $p->a, "/", $p->b, "\n";

$p = new P(...["b" => 99, "a" => 1]);
echo $p->a, "/", $p->b, "\n";

// spread to method
class C {
    public function f(int $a, int $b, int $c): int { return $a + $b + $c; }
}
echo (new C)->f(...[1, 2, 3]), "\n";

// spread to static method
class S {
    public static function calc(int $a, int $b): int { return $a + $b; }
}
echo S::calc(...[5, 10]), "\n";

// passing too few - error
try { add(...[1, 2]); echo "no\n"; }
catch (\ArgumentCountError $e) { echo "ace\n"; }

// passing extra to variadic - all collected
echo sum(...range(1, 5)), "\n"; // 15

// duplicate named args after positional
try {
    fmt(...["name" => "x", "name" => "y"]);
    echo "no\n";
} catch (\Error $e) { echo "dup-name\n"; }

// spread null (architectural - zphp treats as empty array)

// closure with use + spread
$cap = "captured";
$f = function (int $x, int $y) use ($cap) { return "$cap-$x-$y"; };
echo $f(...[1, 2]), "\n";

// destructure + spread
[$a, $b] = [...[10, 20]];
echo "$a/$b\n";

// nested array unpack with string keys
$base = ["a" => 1, "b" => 2];
$ext = [...$base, "c" => 3];
print_r($ext);

// PHP 8.1+: string keys with conflict (later wins)
$result = [...["a" => 1, "b" => 2], "a" => 99];
print_r($result);

// array_merge equivalent via spread
$a = [1, 2, 3];
$b = [4, 5, 6];
print_r([...$a, ...$b]);
