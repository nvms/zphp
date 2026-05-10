<?php
// PHP 8.4 new array functions
echo function_exists("array_find") ? "y" : "n", "\n";
echo function_exists("array_find_key") ? "y" : "n", "\n";
echo function_exists("array_any") ? "y" : "n", "\n";
echo function_exists("array_all") ? "y" : "n", "\n";

// array_find: returns first matching value
$r = array_find([1, 2, 3, 4, 5], fn($v) => $v > 3);
var_dump($r); // 4

$r = array_find([1, 2, 3], fn($v) => $v > 10);
var_dump($r); // null

$r = array_find(["a"=>1, "b"=>2, "c"=>3], fn($v, $k) => $k === "b");
var_dump($r); // 2

// array_find_key: returns first matching key
$k = array_find_key([10, 20, 30, 40], fn($v) => $v > 25);
var_dump($k); // 2 (idx)
$k = array_find_key(["a"=>1, "b"=>2, "c"=>3], fn($v) => $v >= 2);
var_dump($k); // "b"
$k = array_find_key([1,2,3], fn($v) => $v > 10);
var_dump($k); // null

// array_any: returns true if any matches
var_dump(array_any([1, 2, 3], fn($v) => $v > 2)); // true
var_dump(array_any([1, 2, 3], fn($v) => $v > 10)); // false
var_dump(array_any([], fn($v) => true)); // false

// array_all: returns true if all match
var_dump(array_all([1, 2, 3], fn($v) => $v > 0)); // true
var_dump(array_all([1, 2, 3], fn($v) => $v > 1)); // false
var_dump(array_all([], fn($v) => false)); // true (vacuous)

// callbacks with key
var_dump(array_any(["a"=>1, "b"=>2], fn($v, $k) => $k === "a"));
var_dump(array_all(["a"=>1, "b"=>2], fn($v, $k) => is_string($k)));

// callback that throws
try {
    array_find([1, 2, 3], function ($v) {
        if ($v === 2) throw new RuntimeException("at $v");
        return false;
    });
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "caught:", $e->getMessage(), "\n";
}

// existing functions to baseline
print_r(array_filter([1, 2, 3, 4], fn($v) => $v > 2));
print_r(array_map(fn($v) => $v * 10, [1, 2, 3]));

// array_reduce
$sum = array_reduce([1, 2, 3, 4], fn($c, $v) => $c + $v, 0);
echo $sum, "\n"; // 10

// array_reduce with no initial
$sum = array_reduce([1, 2, 3], fn($c, $v) => ($c ?? 0) + $v);
echo $sum, "\n";

// array_filter ARRAY_FILTER_USE_BOTH
print_r(array_filter(["a"=>1, "b"=>2, "c"=>3], fn($v, $k) => $v > 1 && $k !== "c", ARRAY_FILTER_USE_BOTH));

// nested closure with state
$counter = 0;
array_filter([1,2,3], function ($v) use (&$counter) { $counter++; return true; });
echo $counter, "\n"; // 3

// array_walk modifying values
$arr = ["a"=>1, "b"=>2, "c"=>3];
array_walk($arr, function (&$v, $k) { $v = "$k=$v"; });
print_r($arr);
