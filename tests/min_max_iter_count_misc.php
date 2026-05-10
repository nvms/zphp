<?php
// max/min with various types
echo max(1, 2, 3), "\n";
echo max("a", "b", "c"), "\n";
echo min(1.5, 2.5, 0.5), "\n";
echo max([3, 1, 2]), "\n";
echo max(["x", "z", "y"]), "\n";
try { min([]); echo "no\n"; } catch (\ValueError $e) { echo "ve-empty\n"; }

// max with mixed - PHP loose comparison
var_dump(max(1, "1", true)); // 1 (first)
var_dump(max("a", "b", "")); // "b"

// number formatting
echo number_format(1234567.89), "\n"; // 1,234,568 (rounded to int)
echo number_format(1234567.89, 2), "\n";
echo number_format(1234567.89, 0, '', ''), "\n"; // 1234568
echo number_format(0.567, 2), "\n"; // 0.57
echo number_format(-0.567, 2), "\n"; // -0.57

// type checks
var_dump(is_numeric("123"));
var_dump(is_numeric("1.5"));
var_dump(is_numeric("1e10"));
var_dump(is_numeric("abc"));
var_dump(is_numeric("123abc"));
var_dump(is_numeric("  42  "));   // true (trims)
var_dump(is_numeric("0x10"));     // false (PHP 7+)
var_dump(is_numeric("10."));      // true
var_dump(is_numeric(".5"));       // true
var_dump(is_numeric("+1"));       // true
var_dump(is_numeric("-1"));       // true
var_dump(is_numeric(""));         // false
var_dump(is_numeric(null));       // false

// is_callable various
var_dump(is_callable("strlen"));
var_dump(is_callable("nonexistent"));
class C { public function m() {} public static function s() {} }
var_dump(is_callable([new C, 'm']));
var_dump(is_callable(['C', 's']));
var_dump(is_callable('C::s'));
var_dump(is_callable(fn() => 1));

// is_iterable
var_dump(is_iterable([]));
var_dump(is_iterable([1,2]));
var_dump(is_iterable("string"));
function gen() { yield 1; }
var_dump(is_iterable(gen())); // true (Generator)
var_dump(is_iterable(new ArrayIterator([])));

// is_countable
var_dump(is_countable([]));
var_dump(is_countable(new ArrayIterator([])));
var_dump(is_countable(new stdClass));
class K implements Countable { public function count(): int { return 0; } }
var_dump(is_countable(new K));

// array_is_list
var_dump(array_is_list([])); // true
var_dump(array_is_list([1, 2, 3])); // true
var_dump(array_is_list([0 => 1, 1 => 2])); // true
var_dump(array_is_list([0 => 1, 2 => 3])); // false (gap)
var_dump(array_is_list(["a" => 1])); // false
var_dump(array_is_list([1 => "a", 0 => "b"])); // false (out of order)

// compact with mix of vars
$x = 1; $y = "hi"; $z = [3];
print_r(compact("x", "y", "z"));
print_r(compact(["x", "y"]));
print_r(@compact("x", ["y", "z"], "missing")); // PHP warns on undefined

// extract
extract(["a" => 10, "b" => 20, "c" => 30]);
echo "$a $b $c\n";

// extract with prefix
extract(["x" => 100], EXTR_PREFIX_ALL, "p");
echo $p_x ?? "no", "\n";

// extract overwrite default
$x = 1;
extract(["x" => 99]);
echo $x, "\n"; // 99

// EXTR_SKIP - don't overwrite
$x = 1;
extract(["x" => 99, "y" => 2], EXTR_SKIP);
echo $x, ":", $y, "\n"; // 1:2

// list operations
$arr = [1, 2, 3];
[, $b, ] = $arr;
echo $b, "\n";

// PHP doesn't support spread in destructure - skip

// PHP 8.1 enum constants
enum Suit: string {
    case Hearts = "H";
    case Spades = "S";
    case Diamonds = "D";
    case Clubs = "C";

    public function isRed(): bool {
        return $this === self::Hearts || $this === self::Diamonds;
    }
}
foreach (Suit::cases() as $s) echo $s->name, "(", $s->value, ")=", $s->isRed() ? "r" : "b", "|";
echo "\n";

// Enum as array key
$counts = [];
$counts[Suit::Hearts->value] = 13;
$counts[Suit::Spades->value] = 13;
print_r($counts);

// Enum value collision check (compile-time, but test runtime tryFrom)
var_dump(Suit::tryFrom("X"));
var_dump(Suit::tryFrom("H")?->name);
