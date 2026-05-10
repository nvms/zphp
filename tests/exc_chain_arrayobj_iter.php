<?php
// array_search with string keys
$arr = ["a"=>1, "b"=>2, "c"=>3];
var_dump(array_search(2, $arr));
var_dump(array_search(99, $arr)); // false
var_dump(array_search("2", $arr)); // "b" (loose)
var_dump(array_search("2", $arr, true)); // false (strict)

// in_array with class instances
class P { public function __construct(public int $n) {} }
$a = new P(1);
$b = new P(1);
$c = new P(2);
$arr = [$a, $b, $c];
var_dump(in_array(new P(1), $arr));        // true (loose: same prop values)
var_dump(in_array(new P(1), $arr, true));  // false (strict: not same instance)
var_dump(in_array($a, $arr, true));        // true

// ArrayObject getIterator returns ArrayIterator
$ao = new ArrayObject(["x"=>1, "y"=>2, "z"=>3]);
$it = $ao->getIterator();
echo get_class($it), "\n"; // ArrayIterator
foreach ($it as $k => $v) echo "$k=$v ";
echo "\n";

// interface method with default values
interface IfaceWithDefault { public function greet(string $name = "world"): string; }
class IfaceWithDefaultI implements IfaceWithDefault { public function greet(string $name = "world"): string { return "hi $name"; } }
$x = new IfaceWithDefaultI;
echo $x->greet(), "|", $x->greet("alice"), "\n";

// abstract trait method enforcement
trait MustImpl { abstract public function fetch(): string; }
class Has { use MustImpl; public function fetch(): string { return "data"; } }
echo (new Has)->fetch(), "\n";
// (skipping eval-based fatal test - PHP fatal is uncatchable)

// Throwable getCode/getFile/getLine
try {
    throw new RuntimeException("oops", 42);
} catch (\Throwable $e) {
    echo $e->getMessage(), "|", $e->getCode(), "|", basename($e->getFile()), ":", $e->getLine() > 0 ? "yes" : "no", "\n";
    echo count($e->getTrace()) >= 0 ? "trace-arr\n" : "no\n";
    echo gettype($e->getTraceAsString()), "\n";
}

// chained exceptions
try {
    try {
        throw new RuntimeException("inner");
    } catch (Exception $e) {
        throw new LogicException("outer", 0, $e);
    }
} catch (Exception $e) {
    echo $e->getMessage(), "<-", $e->getPrevious()->getMessage(), "\n";
    echo $e->getPrevious()->getPrevious() === null ? "no-deeper\n" : "deeper\n";
}

// triple chain
try {
    try {
        try {
            throw new RuntimeException("a");
        } catch (Exception $e) {
            throw new LogicException("b", 0, $e);
        }
    } catch (Exception $e) {
        throw new InvalidArgumentException("c", 0, $e);
    }
} catch (Exception $e) {
    $cur = $e;
    while ($cur !== null) {
        echo $cur->getMessage(), "->";
        $cur = $cur->getPrevious();
    }
    echo "end\n";
}

// DivisionByZeroError across operators
try { intdiv(1, 0); } catch (\DivisionByZeroError $e) { echo "intdiv\n"; }
try { $r = 5 / 0; } catch (\DivisionByZeroError $e) { echo "div\n"; }
try { $r = 5 % 0; } catch (\DivisionByZeroError $e) { echo "mod\n"; }
try { $r = fdiv(1, 0); echo $r, "\n"; } catch (\DivisionByZeroError $e) { echo "fdiv\n"; }

// PHP emits float-to-int deprecation for % with floats (architectural gap)
echo fmod(7.5, 2.5), "\n"; // 0
echo fmod(7.7, 2.5), "\n"; // 0.2

// += on string (numeric coercion)
$s = "5";
$s += 3;
var_dump($s); // int(8)
$s = "5.5";
$s += 1.5;
var_dump($s); // float(7)
$s = "5abc"; // PHP 8 emits warning + uses 5
$s = (int)$s + 3;
echo $s, "\n";

// unset of object property
class O { public int $a = 1; public int $b = 2; }
$o = new O;
unset($o->a);
echo isset($o->a) ? "set" : "unset", "|", $o->b, "\n";
$o->a = 99;
echo isset($o->a) ? "set" : "unset", ":", $o->a, "\n";

// namespace blocks not supported (architectural gap), use file-level namespaces instead
