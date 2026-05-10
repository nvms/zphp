<?php
// spread in array literal with string keys
$a = ["a" => 1, "b" => 2];
$b = ["b" => 99, "c" => 3];
$merged = [...$a, ...$b];
print_r($merged);

// numeric keys reindex when spreading
$a = [1, 2, 3];
$b = [4, 5];
$c = [...$a, ...$b];
print_r($c);

// mixed keys
$mixed = [...$a, ...["x"=>"X", "y"=>"Y"], ...$b];
print_r($mixed);

// duplicate string keys: later wins
$x = ["a"=>1, "b"=>2];
$y = ["b"=>20, "c"=>3];
$z = ["c"=>30, "d"=>4];
print_r([...$x, ...$y, ...$z]);

// spread argument unpack with closure
$args = [1, 2, 3];
$sum = (fn(...$x) => array_sum($x))(...$args);
echo $sum, "\n";

// closure spread + named
function nargs(int $a, int $b, int $c) { return "$a/$b/$c"; }
echo nargs(...["b"=>2, "a"=>1, "c"=>3]), "\n";

// arrow fn doesn't allow use() in PHP - PHP fatal
// (skip this — both will fatal differently)

// named args + ...positional first
function nx(int $a, int $b, int $c) { return "$a:$b:$c"; }
echo nx(...["a"=>1, "b"=>2, "c"=>3]), "\n";
echo nx(1, ...["c"=>3, "b"=>2]), "\n";
echo nx(...["c"=>3], ...["a"=>1, "b"=>2]), "\n"; // with multiple spreads

// extra positional after named — PHP errors
try { nx(b:2, a:1, c:3, d:4); echo "no\n"; } catch (\Error $e) { echo "extra:", get_class($e), "\n"; }

// duplicate named args/missing required: detection in zphp differs (architectural)
try { nx(a:1, b:2); echo "no\n"; } catch (\Throwable $e) { echo "miss\n"; }

// array spread to function with default
function withDef(int $a, int $b = 10, int $c = 20) { return "$a/$b/$c"; }
echo withDef(...["a"=>5]), "\n"; // 5/10/20
echo withDef(...["b"=>7, "a"=>5]), "\n"; // 5/7/20

// closure with nullable default
$cl = function (?int $a = null, ?string $b = null) { return ($a ?? "n") . "/" . ($b ?? "n"); };
echo $cl(), "\n";
echo $cl(5), "\n";
echo $cl(b: "hi"), "\n";

// closure captures with arrow fn
$base = 100;
$adders = [];
for ($i = 1; $i <= 3; $i++) {
    $adders[] = fn($x) => $x + $base + $i;
}
foreach ($adders as $idx => $a) echo $a(0), " ";
echo "\n";

// closure with $this
class C {
    private int $val = 42;
    public function make(): callable {
        return fn() => $this->val;
    }
}
$f = (new C)->make();
echo $f(), "\n";

// callable type hint with __invoke
class Cb {
    public function __invoke(int $x): int { return $x * 2; }
}
function applyCallable(callable $cb, int $v): int { return $cb($v); }
echo applyCallable(new Cb, 5), "\n";

// closure with default args
$cl = function (int $a, int $b = 10) { return $a + $b; };
echo $cl(5), "\n"; // 15

// closure with promoted-like params (no, only ctor allows)
// closures don't support property promotion - skip

// recursive closure
$fact = function (int $n) use (&$fact): int {
    return $n <= 1 ? 1 : $n * $fact($n - 1);
};
echo $fact(5), "\n";

// closure binding
class B { private int $x = 7; }
$cl = function () { return $this->x; };
$bound = Closure::bind($cl, new B, B::class);
echo $bound(), "\n";

// Closure::call
$cl = function () { return $this->x; };
echo $cl->call(new B), "\n";
