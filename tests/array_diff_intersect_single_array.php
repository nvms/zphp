<?php
// array_diff/array_intersect and their key/assoc variants accept a
// single array (php8) and return that array with its keys preserved

$a = ["x" => 1, 5 => 2, "y" => "2", 0 => 3];

var_dump(array_diff($a) === $a);
var_dump(array_intersect($a) === $a);
var_dump(array_diff_key($a) === $a);
var_dump(array_intersect_key($a) === $a);
var_dump(array_diff_assoc($a) === $a);
var_dump(array_intersect_assoc($a) === $a);

// keys and their order survive exactly (=== above already implies it, but keep
// the shape visible in the output)
print_r(array_diff($a));
print_r(array_intersect($a));
var_dump(array_keys(array_diff_key($a)));

// duplicate values are not collapsed by the single-array form
$dupes = ["a" => 1, "b" => 1, "c" => "1"];
var_dump(array_diff($dupes) === $dupes);
var_dump(array_intersect($dupes) === $dupes);

// empty array stays empty
var_dump(array_diff([]) === []);
var_dump(array_intersect([]) === []);
var_dump(array_diff_assoc([]) === []);
var_dump(array_intersect_assoc([]) === []);

// two-array behavior is unchanged
print_r(array_diff($a, [2]));
print_r(array_intersect($a, [2]));
print_r(array_diff_key($a, ["x" => 0]));
print_r(array_intersect_key($a, ["x" => 0]));
print_r(array_diff_assoc($a, ["x" => 1]));
print_r(array_intersect_assoc($a, ["x" => 1]));
