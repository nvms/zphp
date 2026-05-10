<?php
// PHP 8 named arg / spread combo bugs
function greet(string $name, string $greeting = "hi"): string {
    return "$greeting, $name!";
}
echo greet("alice"), "\n";
echo greet("bob", "hello"), "\n";
echo greet(name: "carol"), "\n";
echo greet(greeting: "yo", name: "dave"), "\n";
echo greet(...["name" => "eve"]), "\n";
echo greet(...["name" => "frank", "greeting" => "ahoy"]), "\n";

// closure with default + spread
$f = fn(int $a, int $b = 10) => "$a/$b";
echo $f(...[5]), "\n";
echo $f(...["a" => 5, "b" => 7]), "\n";
echo $f(...["b" => 7, "a" => 5]), "\n";

// catch (Type) with no var (PHP 8+)
try { throw new \RuntimeException("x"); } catch (\RuntimeException) { echo "caught\n"; }

// readonly property promotion
class Point {
    public function __construct(
        public readonly int $x,
        public readonly int $y,
    ) {}
}
$p = new Point(1, 2);
echo $p->x, ",", $p->y, "\n";
try { $p->x = 5; echo "no\n"; } catch (\Error $e) { echo "ro\n"; }

// nullable, default and null
function t1(?int $a = null, ?string $b = null): string {
    return ($a ?? "n") . "/" . ($b ?? "n");
}
echo t1(), "\n";
echo t1(5), "\n";
echo t1(b: "hi"), "\n";

// nullable returns
function findThing(int $id): ?string {
    return $id > 0 ? "thing-$id" : null;
}
var_dump(findThing(1));
var_dump(findThing(0));

// union type
function isNumeric(int|float|string $v): bool {
    return is_numeric($v);
}
var_dump(isNumeric(42));
var_dump(isNumeric(1.5));
var_dump(isNumeric("123"));

// PHP 8.4: never type, can throw or exit
function failHard(): never {
    throw new RuntimeException("nope");
}
try { failHard(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt:", $e->getMessage(), "\n"; }

// PHP 8.4: explicit promoted readonly
class Vec {
    public function __construct(
        public readonly float $x = 0.0,
        public readonly float $y = 0.0,
        public readonly float $z = 0.0,
    ) {}
    public function __toString(): string { return "({$this->x}, {$this->y}, {$this->z})"; }
}
echo new Vec(1.0, 2.0, 3.0), "\n";
echo new Vec(z: 5.0), "\n"; // (0, 0, 5)

// PHP 8 first-class callable syntax
$f = strlen(...);
echo $f("hello"), "\n";

// Method via first-class
class MyClass { public function go(int $n): int { return $n * 2; } public static function up(string $s): string { return strtoupper($s); } }
$obj = new MyClass;
$f = $obj->go(...);
echo $f(5), "\n";
$f = MyClass::up(...);
echo $f("low"), "\n";

// PHP fatals on nullsafe + closure creation (architectural skip)

// closure ::call
class Bag { private array $items = []; }
$append = function ($x) { $this->items[] = $x; return $this->items; };
print_r($append->call(new Bag, "a"));
print_r($append->call(new Bag, "b"));

// match with no default and unmatched throws
try {
    $r = match(99) { 1 => "a", 2 => "b" };
    echo "no\n";
} catch (\UnhandledMatchError $e) {
    echo "ume\n";
}

// match strict equality
$r = match("1") {
    1 => "int",
    "1" => "str",
    default => "?",
};
echo $r, "\n"; // str (strict)

// match with complex conditions via true
$x = 7;
$r = match(true) {
    $x < 0 => "neg",
    $x === 0 => "zero",
    $x <= 10 => "small",
    default => "big",
};
echo $r, "\n";

// throw expression
$cfg = null;
try {
    $v = $cfg ?? throw new InvalidArgumentException("missing config");
    echo "no\n";
} catch (\InvalidArgumentException $e) {
    echo "iae:", $e->getMessage(), "\n";
}
