<?php
// continue 2 with finally
function nestedContinue() {
    $log = "";
    foreach ([1, 2] as $i) {
        foreach ([10, 20] as $j) {
            try {
                if ($j === 20) continue 2;
                $log .= "$i.$j|";
            } finally {
                $log .= "f$i.$j|";
            }
        }
    }
    return $log;
}
echo nestedContinue(), "\n";

function nestedBreak() {
    $log = "";
    foreach ([1, 2] as $i) {
        foreach ([10, 20] as $j) {
            try {
                if ($i === 2 && $j === 10) break 2;
                $log .= "$i.$j|";
            } finally {
                $log .= "f$i.$j|";
            }
        }
    }
    return $log;
}
echo nestedBreak(), "\n";

// generator inside try with throw
function genThrow() {
    try {
        yield 1;
        throw new RuntimeException("from gen");
        yield 2;
    } catch (RuntimeException $e) {
        yield "caught:" . $e->getMessage();
    } finally {
        yield "fin";
    }
}
foreach (genThrow() as $v) echo "$v ";
echo "\n";

// generator throw from outside
function genTry() {
    try {
        $x = yield 1;
        yield "got:" . $x;
    } catch (Exception $e) {
        yield "caught:" . $e->getMessage();
    }
    yield "after";
}
$g = genTry();
echo $g->current(), "|"; // 1
$g->throw(new Exception("boom"));
echo $g->current(), "|"; // caught:boom
$g->next();
echo $g->current(), "\n"; // after

// trait with constructor
trait WithCtor {
    public string $loaded;
    public function __construct(string $name) { $this->loaded = "loaded:$name"; }
}
class UsesTrait { use WithCtor; }
$u = new UsesTrait("x");
echo $u->loaded, "\n";

// parent constructor
class Animal {
    public function __construct(public string $name, public int $age) {}
}
class Dog extends Animal {
    public function __construct(string $name, int $age, public string $breed) {
        parent::__construct($name, $age);
    }
}
$d = new Dog("rex", 5, "lab");
echo "$d->name/$d->age/$d->breed\n";

// chained parent
class A4 { public function __construct() { echo "A|"; } }
class B4 extends A4 { public function __construct() { parent::__construct(); echo "B|"; } }
class C4 extends B4 { public function __construct() { parent::__construct(); echo "C|"; } }
new C4;
echo "\n";

// array_walk_recursive in iterators
$data = ["a" => 1, "b" => ["c" => 2, "d" => ["e" => 3, "f" => 4]]];
$flat = [];
array_walk_recursive($data, function ($v, $k) use (&$flat) { $flat[$k] = $v; });
ksort($flat);
print_r($flat);

// dechex/hexdec edge
// hexdec("0x10") triggers PHP deprecation, hexdec("ZZ") triggers PHP deprecation; skipped
echo hexdec("10"), "\n";
echo hexdec(""), "\n"; // 0
echo dechex(255), "\n";
echo dechex(0), "\n";
echo dechex(-1), "\n"; // PHP-specific: ffffffffffffffff (signed wrap)

// octdec/decoct
echo octdec("17"), "\n";
echo octdec("0o17"), "\n"; // PHP 8.1+ accepts 0o prefix
echo decoct(8), "\n";

// bindec/decbin
echo bindec("1010"), "\n";
echo bindec("0b1010"), "\n"; // 0b prefix
echo decbin(10), "\n";

// array_combine empty
print_r(array_combine([], []));

// gettype on enum
enum Color { case Red; case Blue; }
echo gettype(Color::Red), "\n"; // object
echo get_class(Color::Red), "\n";

// sprintf %5.2f
echo sprintf("[%5.2f]", 3.14159), "\n";
echo sprintf("[%-10.3f]", 3.14159), "\n";
echo sprintf("[%010.3f]", 3.14159), "\n";
echo sprintf("[%+10.3f]", -3.14159), "\n";
echo sprintf("[% 5.1f]", 3.5), "\n";

// sprintf width zero
echo sprintf("[%0.3f]", 3.14159), "\n"; // [3.142]
echo sprintf("[%.0f]", 3.5), "\n"; // [4]
echo sprintf("[%.0f]", 2.5), "\n"; // [2] (banker's)

// array_pop empty
$a = [];
var_dump(array_pop($a));
$a = [1,2,3];
echo array_pop($a), ":", count($a), "\n";

// array_shift renumbers
$a = [10 => "a", 20 => "b", 30 => "c"];
echo array_shift($a), "\n"; // a
print_r($a); // values renumbered to 0=>b, 1=>c (numeric keys reset)

// array_shift preserves string keys
$a = ["x" => 10, "y" => 20, "z" => 30];
echo array_shift($a), "\n"; // 10
print_r($a);

// str_starts_with empty
var_dump(str_starts_with("hello", ""));
var_dump(str_starts_with("", ""));
var_dump(str_starts_with("", "x"));
var_dump(str_ends_with("hello", ""));
var_dump(str_contains("hello", ""));
var_dump(str_contains("", ""));
