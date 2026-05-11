<?php
print_r(array_keys([1, 2, 3]));
print_r(array_keys(["a" => 1, "b" => 2]));
print_r(array_keys([0 => "x", 5 => "y", "k" => "z"]));
print_r(array_keys([]));

print_r(array_keys([1, 2, 1, 3, 1], 1));
print_r(array_keys(["a" => 1, "b" => 2, "c" => 1], 1));
print_r(array_keys([1, "1", 1.0], 1));
print_r(array_keys([1, "1", 1.0], 1, true));

print_r(array_keys([0, false, null, "", "0"], 0));
print_r(array_keys([0, false, null, "", "0"], 0, true));
print_r(array_keys([0, false, null, "", "0"], false, true));
print_r(array_keys([0, false, null, "", "0"], null, true));

print_r(array_values([1, 2, 3]));
print_r(array_values(["a" => 1, "b" => 2, "c" => 3]));
print_r(array_values([10 => "x", 20 => "y", 30 => "z"]));
print_r(array_values([]));
print_r(array_values(["only"]));

print_r(array_flip([1, 2, 3]));
print_r(array_flip(["a" => 1, "b" => 2, "c" => 3]));
print_r(array_flip(["a" => "x", "b" => "y"]));
print_r(array_flip([]));
print_r(array_flip(["dup" => 1, "other" => 1]));

print_r(array_flip([0, "a"]));

$mixed = [0 => "z", "k" => "v", 1 => "y", 5 => "w"];
print_r(array_keys($mixed));
print_r(array_values($mixed));
print_r(array_flip($mixed));

print_r(array_diff_assoc(["a"=>1, "b"=>2, "c"=>3], ["a"=>1, "b"=>9, "d"=>4]));
print_r(array_diff_assoc(["a"=>1], ["a"=>"1"]));
print_r(array_diff_assoc([1, 2, 3], [1, 2, 3]));
print_r(array_diff_assoc([1, 2, 3], [1, 2]));
print_r(array_diff_assoc(["a"=>1], []));
print_r(array_diff_assoc([], ["a"=>1]));
print_r(array_diff_assoc(["a"=>1, "b"=>2], ["a"=>1, "b"=>2, "c"=>3]));

print_r(array_intersect_assoc(["a"=>1, "b"=>2, "c"=>3], ["a"=>1, "b"=>9, "c"=>3]));
print_r(array_intersect_assoc(["a"=>1], ["a"=>"1"]));
print_r(array_intersect_assoc([1, 2, 3], [1, 2, 3]));
print_r(array_intersect_assoc(["a"=>1], []));
print_r(array_intersect_assoc([], ["a"=>1]));

print_r(array_intersect_assoc(["x"=>1, "y"=>2], ["x"=>1, "y"=>2, "z"=>3]));
print_r(array_diff_assoc(["x"=>1, "y"=>2, "z"=>3], ["x"=>1, "y"=>2]));

print_r(array_diff_assoc(
    ["a"=>1, "b"=>2, "c"=>3, "d"=>4],
    ["a"=>1, "b"=>9],
    ["c"=>3]
));

print_r(array_intersect_assoc(
    ["a"=>1, "b"=>2, "c"=>3, "d"=>4],
    ["a"=>1, "b"=>2, "e"=>5],
    ["a"=>1, "b"=>2, "c"=>3]
));

$arr = ["a" => 1, "b" => 2];
print_r(array_keys($arr));
print_r(array_values($arr));

print_r(array_flip([100 => "a", 200 => "b", 300 => "c"]));

$nested = ["k" => 1, 0 => 1, "j" => 1];
print_r(array_keys($nested, 1));

$with_dup_vals = ["a", "b", "a", "c", "b"];
print_r(array_keys($with_dup_vals, "a"));
print_r(array_keys($with_dup_vals, "b"));

print_r(array_flip(["a", "b", "a", "c"]));

$arr = ["k1" => "alpha", "k2" => "beta", "k3" => "gamma"];
$flipped = array_flip($arr);
print_r($flipped);
echo isset($flipped["alpha"]) ? "y" : "n", "\n";
echo $flipped["alpha"], "\n";

$arr = [1.5, 2.5, 1.5, 3.5];
print_r(array_keys($arr, 1.5));

$arr = ["red", "green", "blue"];
print_r(array_values($arr));

$arr = ["foo" => "bar", "baz" => "qux"];
$keys = array_keys($arr);
print_r($keys);
echo count($keys), "\n";

print_r(array_diff_assoc(
    ["name" => "alice", "age" => 30],
    ["name" => "alice", "age" => 25],
));

print_r(array_intersect_assoc(
    ["name" => "alice", "age" => 30],
    ["name" => "alice", "age" => 25, "city" => "NYC"]
));

$arr = ["a" => "x", "b" => "x", "c" => "y", "d" => "x"];
print_r(array_keys($arr, "x"));

$arr = [1, 2, "1", 2.0, 1];
print_r(array_keys($arr, 1));
print_r(array_keys($arr, 1, true));
