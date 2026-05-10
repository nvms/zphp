<?php
// array_count_values
print_r(array_count_values([1, 1, 2, "1", 2, "a", "a"]));
// PHP: counts: 1=>2 ("1" merges with int 1), 2=>2, "a"=>2

// array_count_values with floats: PHP emits warnings (architectural, skipped)

// array_unique
print_r(array_unique([1, "1", 1.0, true]));
print_r(array_unique([1, 2, 3, 2, 1]));
print_r(array_unique(["a", "b", "a"]));

// SORT_NUMERIC
print_r(array_unique(["1", "01", "1.0", "1e0"], SORT_NUMERIC));
print_r(array_unique(["1", "01", "1.0", "1e0"], SORT_STRING));

// array_unique with objects: both throw Error (skipped exact format)
class V { public function __construct(public int $n) {} }
$arr = [new V(1), new V(2), new V(1)];
try { array_unique($arr); echo "no\n"; } catch (\Error $e) { echo "obj-to-str-err\n"; }

// explode multi-byte separator (byte-based)
print_r(explode(",", "a,b,c"));
print_r(explode(", ", "a, b, c, d"));
print_r(explode("--", "a--b--c"));
print_r(explode("é", "aébécéd"));

// implode with multi-byte
echo implode("é", ["x", "y", "z"]), "\n";
echo bin2hex(implode("é", ["x", "y"])), "\n";

// preg_replace with negative limit
$r = preg_replace('/\d/', 'X', "a1b2c3", -1); // unlimited
echo $r, "\n"; // aXbXcX

// preg_replace with limit
$r = preg_replace('/\d/', 'X', "a1b2c3", 2);
echo $r, "\n"; // aXbXc3

$r = preg_replace('/\d/', 'X', "a1b2c3", 0);
echo $r, "\n"; // a1b2c3 (no replacements)

// preg_split with limit
print_r(preg_split('/,/', "a,b,c,d,e", 3));
print_r(preg_split('/,/', "a,b,c", -1)); // unlimited
print_r(preg_split('/,/', "a,b,c,d", 0)); // PHP: at least 1 element

// PREG_SPLIT_OFFSET_CAPTURE
print_r(preg_split('/,/', "a,b,c", -1, PREG_SPLIT_OFFSET_CAPTURE));

// PREG_SPLIT_DELIM_CAPTURE + OFFSET_CAPTURE
print_r(preg_split('/(,|;)/', "a,b;c", -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_OFFSET_CAPTURE));

// preg_split NO_EMPTY
print_r(preg_split('/,/', ",a,b,,c,", -1, PREG_SPLIT_NO_EMPTY));

// preg_match_all flags combined
preg_match_all('/(\w+)/', "abc def", $m, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
foreach ($m as $set) echo $set[0][0], "@", $set[0][1], "|";
echo "\n";

// preg_replace_callback with limit
$count = 0;
$r = preg_replace_callback('/\d/', fn($m) => 'X', "a1b2c3d4", 2, $count);
echo $r, "|count=$count\n"; // aXbXc3d4|count=2

// preg_match return type details
var_dump(preg_match('/abc/', 'abc def')); // int(1)
var_dump(preg_match('/xyz/', 'abc def')); // int(0)
var_dump(@preg_match('/[/', 'abc'));      // false (compile error)

// preg_grep with PREG_GREP_INVERT
print_r(preg_grep('/\d/', ["abc", "1", "x2", "yz"]));
print_r(preg_grep('/\d/', ["abc", "1", "x2", "yz"], PREG_GREP_INVERT));

// preg_quote with delim
echo preg_quote("Hello!", "/"), "\n";
echo preg_quote("a.b"), "\n";
echo preg_quote("$1.50"), "\n";
