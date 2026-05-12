<?php
// covers: PHP 8 type-strictness edges - in_array strict, array_search strict,
//   strlen coercion, stripos with empty needle, sprintf flags, comparison
//   semantics, intersection types, nullable params, ValueError surface

echo "=== in_array strict vs loose ===\n";
var_dump(in_array('1', [1, 2, 3]));
var_dump(in_array('1', [1, 2, 3], true));
var_dump(in_array(0, ['', 'abc']));
var_dump(array_search('1', [1, 2, 3]));
var_dump(array_search('1', [1, 2, 3], true));

echo "\n=== strlen coerces non-strings ===\n";
var_dump(strlen(123));
var_dump(strlen(45.67));
var_dump(strlen(true));
var_dump(strlen(false));

echo "\n=== empty needle behavior (PHP 8+) ===\n";
var_dump(strpos('hello', ''));
var_dump(stripos('Hello', ''));
var_dump(strrpos('hello', ''));

echo "\n=== PHP 8 equality changes ===\n";
var_dump(0 == "");
var_dump(0 == "0");
var_dump(0 == "abc");
var_dump(null == 0);
var_dump(null == "0");

echo "\n=== numeric strings ===\n";
var_dump(is_numeric("42"));
var_dump(is_numeric("42.5"));
var_dump(is_numeric("4.2e3"));
var_dump(is_numeric("0x1A"));
var_dump(is_numeric(" 42"));
var_dump(is_numeric("42 "));
var_dump(is_numeric("hello"));

echo "\n=== strict_types in nested files ===\n";
function takes_id(int|string $id): string { return "id=$id"; }
echo takes_id(1) . "\n";
echo takes_id('abc') . "\n";

echo "\n=== intersection types ===\n";
interface Loggable { public function log(): void; }
interface Cacheable { public function cache(): void; }
function logAndCache(Loggable&Cacheable $x): string { return 'both ok'; }
class Service implements Loggable, Cacheable {
    public function log(): void {}
    public function cache(): void {}
}
echo logAndCache(new Service()) . "\n";

echo "\n=== readonly enforcement ===\n";
class Point { public function __construct(public readonly int $x, public readonly int $y) {} }
$p = new Point(1, 2);
echo "x=$p->x y=$p->y\n";
try { $p->x = 99; } catch (Error $e) { echo "readonly: blocked\n"; }

echo "\n=== sprintf padding & precision ===\n";
echo sprintf("%05d\n", 42);
echo sprintf("%-10s|\n", "abc");
echo sprintf("%.3f\n", 3.14159);
echo sprintf("%+.2f\n", 3.14);
echo sprintf("%x %X\n", 255, 255);
echo sprintf("%o\n", 8);
echo sprintf("%b\n", 10);
echo sprintf("%e\n", 1234567);

echo "\n=== intdiv vs (int)/ ===\n";
var_dump(intdiv(10, 3));
var_dump((int)(10 / 3));
var_dump(intdiv(-10, 3));
var_dump(fmod(5.5, 2));

echo "\n=== number_format locales ===\n";
echo number_format(1234567.891) . "\n";
echo number_format(1234567.891, 2) . "\n";
echo number_format(1234567.891, 2, '.', ',') . "\n";
echo number_format(1234567.891, 2, ',', '.') . "\n";

echo "\n=== array_combine ValueError ===\n";
try {
    array_combine(['a','b'], [1]);
    echo "no throw\n";
} catch (ValueError $e) {
    echo "ValueError caught\n";
}

echo "\n=== spaceship ordering ===\n";
$xs = [3, 1, 4, 1, 5, 9, 2, 6];
usort($xs, fn($a, $b) => $a <=> $b);
echo implode(',', $xs) . "\n";
usort($xs, fn($a, $b) => $b <=> $a);
echo implode(',', $xs) . "\n";

echo "\n=== nullsafe chain ===\n";
class A { public ?B $b = null; }
class B { public ?C $c = null; }
class C { public string $val = "found"; }
$a = new A();
echo "no chain: '" . ($a->b?->c?->val ?? "missing") . "'\n";
$a->b = new B();
$a->b->c = new C();
echo "full chain: '" . $a->b?->c?->val . "'\n";

echo "\ndone\n";
