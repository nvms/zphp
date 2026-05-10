<?php
// array_walk_recursive on iterators - PHP 8 throws TypeError
$src = new ArrayIterator([1, 2, 3]);
try {
    array_walk_recursive($src, function (&$v) { $v *= 10; });
    echo "no err\n";
} catch (\TypeError $e) { echo "te:awr-iter\n"; }

// PHP emits a "by-reference" Notice for non-array array_walk_recursive (architectural)

// str_replace count by-ref
$count = 0;
$r = str_replace("a", "X", "banana", $count);
echo "$r:$count\n"; // bXnXnX:3

$count = 0;
$r = str_replace(["a", "n"], "_", "banana", $count);
echo "$r:$count\n";

// str_replace count with array subjects
$count = 0;
$r = str_replace("a", "X", ["abc", "ban", "ana"], $count);
print_r($r);
echo "count=$count\n"; // 1+1+2 = 4

// str_ireplace
echo str_ireplace("HELLO", "BYE", "hello world Hello"), "\n"; // BYE world BYE
$count = 0;
$r = str_ireplace("o", "0", "Hello World", $count);
echo "$r:$count\n"; // Hell0 W0rld:2

// str_ireplace with arrays
echo str_ireplace(["A", "E", "I"], ["1", "2", "3"], "Apple Engine"), "\n";

// substr_replace with array subjects
$arr = ["hello", "world", "foo"];
$r = substr_replace($arr, "X", 1, 2);
print_r($r);

// substr_replace with array of replacements (one per subject)
$r = substr_replace($arr, ["A", "B", "C"], 1, 2);
print_r($r);

// substr_replace with array subj + array offset/length
$r = substr_replace($arr, "Z", [1, 2, 0], [2, 1, 1]);
print_r($r);

// str_contains case-sensitivity
var_dump(str_contains("Hello World", "world")); // false
var_dump(str_contains("Hello World", "World")); // true
// no built-in case-insensitive str_contains; use stripos
var_dump(stripos("Hello World", "WORLD") !== false);

// mb_str_pad (PHP 8.3+)
if (function_exists('mb_str_pad')) {
    echo mb_str_pad("héllo", 10, "-", STR_PAD_RIGHT), "|\n";
    echo mb_str_pad("héllo", 10, "-", STR_PAD_LEFT), "|\n";
    echo mb_str_pad("héllo", 10, "-", STR_PAD_BOTH), "|\n";
} else {
    echo "no-mb_str_pad\n";
}

// mb_strpos
echo mb_strpos("héllo wörld", "wö"), "\n";
echo mb_strpos("héllo wörld", "ö"), "\n";

// mb_strpos with offset
echo mb_strpos("aaaba", "a", 2), "\n"; // 2 (zero-based char index)
echo mb_strpos("aaaba", "a", 3), "\n"; // 4
var_dump(mb_strpos("abc", "x"));

// mb_stripos (case-insensitive)
echo mb_stripos("Héllo WÖRLD", "wörld"), "\n"; // 6 (char index)
var_dump(mb_stripos("abc", "X"));

// mb_substr_count
echo mb_substr_count("ababab", "ab"), "\n"; // 3
echo mb_substr_count("héllo", "é"), "\n"; // 1

// mb_strtolower with non-ASCII
echo mb_strtolower("HÉLLO"), "\n";
echo mb_strtolower("STRAßE"), "\n"; // straße (or strase in some locales)
echo mb_strtoupper("groß"), "\n"; // GROSS

// mb_convert_case
echo mb_convert_case("hello world", MB_CASE_TITLE), "\n";
echo mb_convert_case("HELLO WORLD", MB_CASE_LOWER), "\n";
echo mb_convert_case("hello WORLD", MB_CASE_UPPER), "\n";

// mb_substr negatives
echo mb_substr("héllo", -2), "\n";
echo mb_substr("héllo", 0, -1), "\n";
echo mb_substr("héllo", 1, 3), "\n";

// mb_str_split
print_r(mb_str_split("héllo", 2));

// str_word_count edge
echo str_word_count(""), "\n"; // 0
echo str_word_count("hello"), "\n"; // 1
print_r(str_word_count("hello world", 1));
print_r(str_word_count("hello world", 2));
