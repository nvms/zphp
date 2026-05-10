<?php
// closure with spread params
$fn = function (...$args) { return array_sum($args); };
echo $fn(1, 2, 3, 4), "\n"; // 10
echo $fn(), "\n"; // 0

$fn = function (int $first, ...$rest) { return $first + count($rest); };
echo $fn(10, 1, 2, 3), "\n"; // 13

// named args with spread (PHP 8.1+)
function namedSpread(int $a, int $b, int $c) { return "$a/$b/$c"; }
$args = ["b" => 20, "a" => 10, "c" => 30];
echo namedSpread(...$args), "\n";

// mixing positional and named
echo namedSpread(10, ...["c" => 30, "b" => 20]), "\n";

// intersection types runtime check
interface Countable2 { public function count(): int; }
interface Named2 { public function name(): string; }

class Box implements Countable2, Named2 {
    public function count(): int { return 5; }
    public function name(): string { return "box"; }
}

class OnlyCount implements Countable2 {
    public function count(): int { return 3; }
}

function process(Countable2&Named2 $thing): string { return $thing->name() . ":" . $thing->count(); }

echo process(new Box), "\n";
try { process(new OnlyCount); echo "no\n"; } catch (\TypeError $e) { echo "te-intersect\n"; }

// never return enforcement: PHP fatals (uncatchable), skipped

// abstract method in concrete class - PHP fatal at class definition
// Just test that abstract method works correctly
abstract class Base {
    abstract public function impl(): string;
}
class Concrete extends Base {
    public function impl(): string { return "real"; }
}
echo (new Concrete)->impl(), "\n";

try {
    $obj = (new ReflectionClass(Base::class))->newInstance();
    echo "no\n";
} catch (\Error $e) { echo "abstract-err\n"; }

// Closure use of spread
$mult = 3;
$fn = function (...$nums) use ($mult) { return array_sum($nums) * $mult; };
echo $fn(1, 2, 3), "\n"; // 18

// arrow with multiple captures
$a = 10;
$b = 20;
$fn = fn($x) => $x + $a + $b;
echo $fn(5), "\n"; // 35

// closure with reference capture
$counter = 0;
$inc = function () use (&$counter) { return ++$counter; };
echo $inc(), $inc(), $inc(), "\n"; // 123

// closure binding to enum
enum Color { case Red; case Blue; }
$cl = function () { return self::class; };
$bound = Closure::bind($cl, null, Color::class);
echo $bound(), "\n";

// static closure cannot bind
$sc = static function () { return self::class; };
$bound = Closure::bind($sc, null, Color::class);
echo $bound(), "\n";

// Recursive closure
$factorial = function (int $n) use (&$factorial): int {
    return $n <= 1 ? 1 : $n * $factorial($n - 1);
};
echo $factorial(5), "\n"; // 120

// throw expression in arrow
$div = fn($a, $b) => $b === 0 ? throw new DivisionByZeroError("zero") : $a / $b;
echo $div(10, 2), "\n";
try { $div(10, 0); echo "no\n"; } catch (\DivisionByZeroError $e) { echo "div0\n"; }

// match in arrow
$describe = fn($v) => match(true) {
    $v < 0 => "neg",
    $v === 0 => "zero",
    $v > 0 => "pos",
};
echo $describe(-5), ":", $describe(0), ":", $describe(7), "\n";

// nested match
$f = fn($x) => match($x) {
    1, 2, 3 => match(true) {
        $x === 2 => "two",
        default => "low",
    },
    default => "high",
};
echo $f(1), ":", $f(2), ":", $f(3), ":", $f(99), "\n";
