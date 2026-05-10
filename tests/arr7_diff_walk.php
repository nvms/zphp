<?php
// array_diff_assoc with mixed keys
print_r(array_diff_assoc(["a"=>1, "b"=>2, "c"=>3], ["a"=>1, "b"=>9]));
print_r(array_diff_assoc([0=>"a", 1=>"b", 2=>"c"], [0=>"a", 1=>"x"]));
print_r(array_diff_assoc(["a"=>1, 0=>2, "c"=>3], [0=>2, "a"=>1]));

// array_intersect_assoc
print_r(array_intersect_assoc(["a"=>1, "b"=>2, "c"=>3], ["a"=>1, "b"=>9, "d"=>3]));
print_r(array_intersect_assoc([1,2,3], [1,9,3]));

// array_intersect (values)
print_r(array_intersect([1,2,3,4], [2,3,5]));
print_r(array_intersect(["a","b","c"], ["b","c","d"]));

// array_replace_recursive depth
$base = [
    "a" => 1,
    "b" => [
        "x" => 10,
        "y" => 20,
        "deep" => ["a" => 1, "b" => 2],
    ],
    "c" => 3,
];
$over = [
    "b" => [
        "x" => 99,
        "deep" => ["a" => 100],
    ],
    "d" => 4,
];
print_r(array_replace_recursive($base, $over));

// array_merge_recursive
$a = ["color" => ["fav" => "red", "blue"], "fruit" => "apple"];
$b = ["color" => ["fav" => "green", "yellow"], "fruit" => ["banana", "kiwi"]];
print_r(array_merge_recursive($a, $b));

// array_merge (no recursion)
print_r(array_merge($a, $b));

// array_walk modifying keys (key is read-only in callback)
$arr = ["a" => 1, "b" => 2, "c" => 3];
array_walk($arr, function (&$v, $k) {
    $v = "$k:$v";
});
print_r($arr);

// array_walk with use
$mult = 10;
$arr = [1, 2, 3];
array_walk($arr, function (&$v) use ($mult) { $v *= $mult; });
print_r($arr);

// array_walk extra arg
$arr = [1, 2, 3];
array_walk($arr, function (&$v, $k, $factor) { $v *= $factor; }, 100);
print_r($arr);

// array_walk preserves order
$arr = ["z"=>1, "a"=>2, "m"=>3];
array_walk($arr, function (&$v) { $v *= 2; });
foreach ($arr as $k => $v) echo "$k=$v ";
echo "\n";

// array_walk_recursive
$nested = ["a" => 1, "b" => ["x" => 2, "y" => ["deep" => 3]]];
array_walk_recursive($nested, function (&$v) { $v *= 10; });
print_r($nested);

// array_unique on associative
print_r(array_unique(["a"=>1, "b"=>1, "c"=>2, "d"=>1]));

// array_count_values
print_r(array_count_values(["a","b","a","c","b","a"]));
print_r(array_count_values([1, 1, 2, 3, 1]));

// array_flip
print_r(array_flip(["a","b","c"]));
print_r(array_flip(["x"=>1, "y"=>2]));

// array_search returning false
var_dump(array_search("x", ["a","b","c"]));
var_dump(array_search("a", ["a","b","c"]));

// in_array
var_dump(in_array(0, ["a", "b"])); // false (PHP 8)
var_dump(in_array("a", ["a", "b"]));

// array_combine + array_flip
$arr = array_combine(["a","b","c"], [1,2,3]);
print_r(array_flip($arr));

// nested map+filter
$data = [1,2,3,4,5,6];
$result = array_map(fn($x) => $x * 2, array_filter($data, fn($x) => $x % 2 === 0));
print_r($result);

// array_reduce with initial
$sum = array_reduce([1,2,3,4], fn($c, $v) => $c + $v, 100);
echo $sum, "\n"; // 110

// array_reduce returning object/array
$result = array_reduce(["a","b","c"], fn($c, $v) => array_merge($c, [$v]), []);
print_r($result);
