<?php

// array_find
function is_even($v) { return $v % 2 === 0; }
echo array_find([1, 3, 5, 4, 7], "is_even") . "\n";
echo var_export(array_find([1, 3, 5], "is_even"), true) . "\n";

// array_find_key
echo array_find_key([1, 3, 5, 4, 7], "is_even") . "\n";

// array_find with string keys
function starts_with_a($v) { return str_starts_with($v, "a"); }
$fruits = ["x" => "banana", "y" => "apple", "z" => "avocado"];
echo array_find($fruits, "starts_with_a") . "\n";
echo array_find_key($fruits, "starts_with_a") . "\n";

// array_any
echo var_export(array_any([1, 3, 5, 4], "is_even"), true) . "\n";
echo var_export(array_any([1, 3, 5], "is_even"), true) . "\n";

// array_all
function is_positive($v) { return $v > 0; }
echo var_export(array_all([1, 2, 3], "is_positive"), true) . "\n";
echo var_export(array_all([1, -2, 3], "is_positive"), true) . "\n";
echo var_export(array_all([], "is_positive"), true) . "\n";

// mb_trim
echo mb_trim("  hello  ") . "\n";
echo mb_trim("xxhelloxx", "x") . "\n";
echo mb_ltrim("  hello  ") . "\n";
echo mb_rtrim("  hello  ") . "\n";
