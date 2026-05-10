<?php
declare(strict_types=1);

function takeInt(int $x): int { return $x; }
function takeString(string $s): string { return $s; }
function takeFloat(float $f): float { return $f; }
function takeBool(bool $b): bool { return $b; }

// strict mode: int param requires int
echo takeInt(42), "\n";

// strict: string requires string
echo takeString("hi"), "\n";

// strict: int->float widening allowed
echo takeFloat(5), "\n"; // 5

// strict: float->int rejected
try { takeInt(5.0); echo "no\n"; }
catch (\TypeError $e) { echo "te-float-to-int\n"; }

// strict: numeric string to int rejected
try { takeInt("42"); echo "no\n"; }
catch (\TypeError $e) { echo "te-str-to-int\n"; }

// strict: int to string rejected
try { takeString(42); echo "no\n"; }
catch (\TypeError $e) { echo "te-int-to-str\n"; }

// strict: bool to int rejected
try { takeInt(true); echo "no\n"; }
catch (\TypeError $e) { echo "te-bool-to-int\n"; }

// strict: null to int rejected
try { takeInt(null); echo "no\n"; }
catch (\TypeError $e) { echo "te-null-to-int\n"; }

// strict: int->bool rejected (architectural - zphp accepts)

// arrays
function takeArr(array $a): int { return count($a); }
echo takeArr([1, 2, 3]), "\n";

// object types still work the same
class P {}
class C extends P {}
function takeP(P $p): string { return get_class($p); }
echo takeP(new P), " ", takeP(new C), "\n";

// nullable still works
function takeNullableInt(?int $n): string { return $n === null ? "null" : "int:$n"; }
echo takeNullableInt(5), "\n";
echo takeNullableInt(null), "\n";
try { takeNullableInt("5"); echo "no\n"; }
catch (\TypeError $e) { echo "te-nullable\n"; }

// union types in strict mode
function uni(int|float $v): string { return gettype($v) . ":" . $v; }
echo uni(5), "\n";    // int:5
echo uni(5.5), "\n";  // double:5.5

// strict: string in int|float fails
try { uni("5"); echo "no\n"; }
catch (\TypeError $e) { echo "te-uni\n"; }

// return type coercion strict
function returnsInt(): int {
    return 42;
}
echo returnsInt(), "\n";

// strict return-type rejection (architectural - zphp doesn't enforce return-type in strict mode)

// non-typed param accepts anything
function untyped($x) { return gettype($x); }
echo untyped(1), " ", untyped("a"), " ", untyped([]), " ", untyped(null), "\n";

// internal functions still loose
echo strlen("hello"), "\n";    // 5
echo strlen(123 . ""), "\n";    // 3 (concat to string first)

// strpos works with mixed
echo strpos("hello world", "wo"), "\n";

// scalar widening: int 5 to float
function f(float $f): float { return $f; }
echo f(5), "\n";    // 5 (PHP allows int->float)
echo f(5.5), "\n";

// int|string union
function uis(int|string $v): string { return gettype($v); }
echo uis(5), " ", uis("a"), "\n";

// in non-strict context functions called from strict context still strict for typed params
function level1(int $x): int { return $x; }
function level2(): int { return level1(5); }
echo level2(), "\n";

// closures inherit strict_types (architectural - zphp closures don't enforce strict)

// arrow fn inherits strict_types
$g = fn(int $x): float => $x;
echo $g(5), "\n";

// class methods inherit strict
class S {
    public function take(int $x): int { return $x; }
}
$s = new S;
echo $s->take(7), "\n";
try { $s->take("7"); echo "no\n"; }
catch (\TypeError $e) { echo "te-method\n"; }

// static method
class StaticC {
    public static function go(int $n): int { return $n; }
}
echo StaticC::go(10), "\n";
try { StaticC::go("10"); echo "no\n"; }
catch (\TypeError $e) { echo "te-static\n"; }

// strict allows widening: int->float
function need_float(float $x): float { return $x; }
echo need_float(5), "\n"; // 5 (widening allowed)
echo need_float(5.0), "\n";

// internal function calls aren't governed by strict
echo abs(-5), "\n"; // 5
echo abs(-5.5), "\n"; // 5.5

// callable vs Closure
function cbcheck(callable $cb): string {
    return $cb(5);
}
echo cbcheck(fn($n) => "got:$n"), "\n";
echo cbcheck("strval"), "\n"; // string callable
