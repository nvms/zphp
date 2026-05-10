<?php
// array_map multiple arrays
print_r(array_map(fn($a, $b) => $a + $b, [1, 2, 3], [10, 20, 30]));
print_r(array_map(fn($a, $b) => "$a-$b", ["a", "b", "c"], [1, 2, 3]));

// array_map with null callback (zip)
print_r(array_map(null, [1, 2, 3], ["a", "b", "c"]));

// array_map with different lengths (pads with null)
print_r(array_map(fn($a, $b) => [$a, $b], [1, 2], [10, 20, 30]));

// array_map single array
print_r(array_map(fn($x) => $x * 2, [1, 2, 3]));

// array_map preserves keys (single array)
print_r(array_map(fn($x) => $x * 2, ["a" => 1, "b" => 2]));

// array_map drops keys (multiple arrays)
print_r(array_map(fn($a, $b) => $a + $b, ["x" => 1, "y" => 2], ["x" => 10, "y" => 20]));

// array_walk modifies in place (by ref)
$arr = [1, 2, 3];
array_walk($arr, function (&$v) { $v *= 10; });
print_r($arr);

// array_walk with key
$arr = ["a" => 1, "b" => 2];
array_walk($arr, function (&$v, $k) { $v = "$k=$v"; });
print_r($arr);

// array_walk with extra arg
$arr = [1, 2, 3];
array_walk($arr, function (&$v, $k, $factor) { $v *= $factor; }, 100);
print_r($arr);

// array_walk_recursive
$arr = [1, [2, [3, 4]]];
array_walk_recursive($arr, function (&$v) { $v *= 10; });
print_r($arr);

// array_filter with no callback - truthy default
print_r(array_filter([0, 1, 2, "", "x", null, false, "0", " ", []]));

// array_filter ARRAY_FILTER_USE_KEY
$arr = ["a" => 1, "b" => 2, "c" => 3];
print_r(array_filter($arr, fn($k) => $k !== "b", ARRAY_FILTER_USE_KEY));

// array_filter ARRAY_FILTER_USE_BOTH
print_r(array_filter($arr, fn($v, $k) => $v > 1 && $k !== "c", ARRAY_FILTER_USE_BOTH));

// array_combine
print_r(array_combine([1, 2, 3], ["a", "b", "c"]));
print_r(array_combine(["x", "y", "z"], [10, 20, 30]));

// array_combine with int->string keys
$keys = [1, 2, 3];
$values = ["a", "b", "c"];
print_r(array_combine($keys, $values));

// keys cast: floats truncate, bools to int, null to ""
print_r(array_combine([1.5, 2.5, 3.5], ["a", "b", "c"]));
print_r(array_combine([true, false], ["x", "y"]));
print_r(array_combine([null], ["nothing"]));

// duplicate keys: last wins
print_r(array_combine([1, 2, 1], ["a", "b", "c"]));

// length mismatch throws
try { array_combine([1, 2], [1, 2, 3]); echo "no\n"; }
catch (\ValueError $e) { echo "ve\n"; }

// range int
print_r(range(1, 5));
print_r(range(5, 1));
print_r(range(1, 10, 2));
print_r(range(10, 1, 2));

// range float
print_r(range(0, 1, 0.25));
print_r(range(0.5, 2.5, 0.5));

// range char
print_r(range("a", "e"));
print_r(range("z", "v"));
print_r(range("A", "C"));

// range single element
print_r(range(5, 5));
print_r(range("a", "a"));

// range with negative step
print_r(range(10, 1, -1));

// array_keys / array_values
print_r(array_keys(["a" => 1, "b" => 2]));
print_r(array_values(["a" => 1, "b" => 2]));

// array_keys with filter
print_r(array_keys([1, 2, 1, 3, 1], 1));

// array_flip
print_r(array_flip(["a" => 1, "b" => 2, "c" => 3]));

// array_flip with duplicate values (last key wins)
print_r(array_flip([1, 1, 2, 2, 3]));

// array_chunk
print_r(array_chunk([1, 2, 3, 4, 5], 2));
print_r(array_chunk([1, 2, 3, 4, 5], 2, true)); // preserve keys

// array_slice
print_r(array_slice([1, 2, 3, 4, 5], 1));
print_r(array_slice([1, 2, 3, 4, 5], 1, 2));
print_r(array_slice([1, 2, 3, 4, 5], -2));
print_r(array_slice(["a" => 1, "b" => 2, "c" => 3], 1));
print_r(array_slice(["a" => 1, "b" => 2, "c" => 3], 1, 1, true));

// array_splice
$arr = [1, 2, 3, 4, 5];
$removed = array_splice($arr, 1, 2, ["x", "y", "z"]);
print_r($arr);
print_r($removed);

// array_pad
print_r(array_pad([1, 2, 3], 5, 0));
print_r(array_pad([1, 2, 3], -5, 0));
print_r(array_pad([1, 2, 3], 2, 0));
