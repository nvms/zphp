<?php
// readonly properties
class Point { public function __construct(public readonly float $x, public readonly float $y) {} }
$p = new Point(1.0, 2.0);
echo $p->x, ",", $p->y, "\n";
try { $p->x = 9.0; echo "no err\n"; } catch (\Error $e) { echo "ro:", $e->getMessage(), "\n"; }

// enum cases
enum Color: string {
    case Red = "red";
    case Blue = "blue";
    case Green = "green";

    public function hex(): string {
        return match($this) {
            Color::Red => "#f00",
            Color::Blue => "#00f",
            Color::Green => "#0f0",
        };
    }
}
echo Color::Red->hex(), "\n";
echo Color::Red->value, "\n";
echo Color::Red->name, "\n";
$c = Color::from("blue");
echo $c->name, "\n";
$c = Color::tryFrom("nope");
var_dump($c); // null
print_r(Color::cases());

// first-class callable
$fn = strlen(...);
echo $fn("hello"), "\n";

class Foo { public function bar(int $x): int { return $x * 2; } public static function baz(int $x): int { return $x + 1; } }
$f = new Foo;
$cb = $f->bar(...);
echo $cb(5), "\n";
$sb = Foo::baz(...);
echo $sb(10), "\n";

// match expression
$v = 3;
$r = match(true) {
    $v < 2 => "small",
    $v < 5 => "medium",
    default => "large",
};
echo $r, "\n";

$r = match($v) {
    1, 2, 3 => "low",
    4, 5, 6 => "mid",
    default => "high",
};
echo $r, "\n";

try { $r = match(99) { 1 => "one" }; } catch (\UnhandledMatchError $e) { echo "ume\n"; }

// arrow functions capture by value
$mult = 3;
$f = fn($x) => $x * $mult;
echo $f(4), "\n";
$mult = 10;
echo $f(4), "\n"; // still 12

// null coalescing assignment
$a = null;
$a ??= "default";
echo $a, "\n";
$a ??= "other";
echo $a, "\n";
$arr = [];
$arr["x"] ??= 42;
echo $arr["x"], "\n";

// nested ternary requires parens (PHP 8 fatal without)
$v = 5;
echo ($v > 0 ? ($v < 10 ? "small-pos" : "big-pos") : "neg"), "\n";

// ?->
class Box { public ?Box $next = null; public int $v; public function __construct(int $v) { $this->v = $v; } }
$b = new Box(1);
$b->next = new Box(2);
echo $b->next?->v, "\n"; // 2
echo $b->next?->next?->v ?? "null", "\n"; // null
echo $b->next?->next?->v, "|\n"; // empty

// named arguments
function namedTest(int $a, string $b = "x", float $c = 1.0): string { return "$a-$b-$c"; }
echo namedTest(a: 1, c: 2.5), "\n";
echo namedTest(b: "y", a: 7), "\n";

// variadic with spread
function vsum(int ...$nums) { return array_sum($nums); }
echo vsum(1,2,3,4), "\n";
$args = [10,20,30];
echo vsum(...$args), "\n";
echo vsum(5, ...$args), "\n";

// destructuring
["a" => $x, "b" => $y] = ["a" => 1, "b" => 2, "c" => 3];
echo "$x,$y\n";
[$first, , $third] = [10, 20, 30];
echo "$first,$third\n";

// array spread (8.1+)
$base = [1, 2, 3];
$ext = [0, ...$base, 4];
print_r($ext);

// string interp complex
$obj = new stdClass; $obj->name = "world";
echo "hello {$obj->name}!\n";
$arr = ["k" => "v"];
echo "val={$arr["k"]}\n";

// heredoc/nowdoc
echo <<<EOT
multi
line
EOT, "\n";

echo <<<'NOW'
no $interp here
NOW, "\n";
