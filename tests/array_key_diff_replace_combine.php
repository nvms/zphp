<?php
print_r(array_diff_key(["a" => 1, "b" => 2, "c" => 3], ["b" => 0]));
print_r(array_diff_key([1, 2, 3], [1 => 0]));

print_r(array_diff_key(["a" => 1, 0 => 2, "b" => 3], ["a" => 0, 1 => 0]));

print_r(array_diff_key([1 => "a", "1" => "b"], [1 => "x"]));

print_r(array_diff_key(["a" => 1], []));
print_r(array_diff_key([], ["a" => 1]));

print_r(array_diff_key(["a" => 1], ["a" => 9], ["b" => 0]));

print_r(array_intersect_key(["a" => 1, "b" => 2, "c" => 3], ["b" => 99]));
print_r(array_intersect_key(["a" => 1, "b" => 2], ["a" => 9, "c" => 3]));

print_r(array_intersect_key([0 => "x", 1 => "y", 2 => "z"], [1 => "a"]));

print_r(array_intersect_key(["a" => 1], ["a" => 2], ["a" => 3]));
print_r(array_intersect_key(["a" => 1, "b" => 2], ["a" => 3], ["b" => 4]));

print_r(array_replace(
    ["a" => 1, "b" => 2],
    ["b" => 99, "c" => 3],
));

print_r(array_replace(
    ["x", "y"],
    [10],
));

print_r(array_replace(
    ["a" => 1, "b" => ["x" => 1, "y" => 2]],
    ["b" => ["x" => 99, "z" => 3]],
));

print_r(array_replace_recursive(
    ["a" => 1, "b" => ["x" => 1, "y" => 2]],
    ["b" => ["x" => 99, "z" => 3]],
));

print_r(array_replace_recursive(
    ["a" => 1, "b" => ["x" => 1, "y" => 2, "z" => 5]],
    ["b" => ["y" => 99]],
));

print_r(array_replace_recursive(
    ["nest" => [1, 2, 3]],
    ["nest" => [9, 9]],
));

print_r(array_replace_recursive(
    ["users" => [["name" => "alice"], ["name" => "bob"]]],
    ["users" => [0 => ["name" => "ALICE"]]],
));

print_r(array_combine(["a", "b", "c"], [1, 2, 3]));
print_r(array_combine([1, 2, 3], ["x", "y", "z"]));
print_r(array_combine(["a"], [42]));
print_r(array_combine([], []));

print_r(array_combine(["a", "b", "a"], [1, 2, 3]));

print_r(array_combine([true, false], ["a", "b"]));
print_r(array_combine([1.5, 2.5], ["a", "b"]));
print_r(array_combine([null], ["x"]));

try { array_combine(["a", "b"], ["x"]); echo "no\n"; }
catch (\ValueError $e) { echo "ve\n"; }

print_r(array_diff_key(["a" => 1, "b" => 2], ["a" => 1, "c" => 3]));

print_r(array_diff_key(["b" => 2, "a" => 1], ["a" => 0]));

$keys = ["a" => 0, "b" => 0];
$vals = ["a" => 1, "b" => 2, "c" => 3];
print_r(array_intersect_key($vals, $keys));

print_r(array_replace(
    [1, 2, 3, 4, 5],
    [10],
    [],
    [99 => "extra"],
));

print_r(array_replace(
    [],
    [1, 2, 3],
));

print_r(array_replace(
    ["a" => 1],
    ["a" => 2],
    ["a" => 3],
));

$arr = ["a" => 1, "b" => 2, "c" => 3];
$keys = array_keys($arr);
$vals = array_values($arr);
print_r(array_combine($keys, $vals));
print_r(array_combine($vals, $keys));

$lookup = array_flip(["alpha", "beta", "gamma"]);
print_r($lookup);
echo $lookup["beta"], "\n";

$config_def = ["host" => "localhost", "port" => 5432, "db" => "test"];
$config_user = ["port" => 3306, "user" => "admin"];
print_r(array_replace($config_def, $config_user));

$tree_def = ["a" => ["x" => 1, "y" => 2], "b" => 5];
$tree_user = ["a" => ["x" => 100], "c" => 9];
print_r(array_replace_recursive($tree_def, $tree_user));
