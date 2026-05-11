<?php
$arr = ["a" => 1, "b" => 2, "c" => 3];
array_walk($arr, function (&$v, $k) { $v *= 10; });
print_r($arr);

$arr = [10, 20, 30];
array_walk($arr, function (&$v, $k) { $v = "$k:$v"; });
print_r($arr);

$arr = ["x" => "alpha", "y" => "beta"];
array_walk($arr, function (&$v, $k) { $v = strtoupper($v); });
print_r($arr);

$arr = [1, 2, 3];
array_walk($arr, function ($v, $k) {
    echo "$k=$v ";
});
echo "\n";
print_r($arr);

$arr = [1, 2, 3, 4, 5];
array_walk($arr, function (&$v) { $v *= $v; });
print_r($arr);

$arr = ["k1" => 1, "k2" => 2];
array_walk($arr, function (&$v, $k, $extra) { $v = "$v-$extra"; }, "tag");
print_r($arr);

$arr = ["a" => 1, "b" => 2];
array_walk($arr, function (&$v, $k, $mult) { $v *= $mult; }, 100);
print_r($arr);

$nested = [
    "a" => [1, 2, 3],
    "b" => ["x" => 10, "y" => 20],
];
array_walk_recursive($nested, function (&$v, $k) { $v *= 2; });
print_r($nested);

$nested = [[1, [2, 3]], [4, [5, [6, 7]]]];
array_walk_recursive($nested, function (&$v) { $v += 100; });
print_r($nested);

$arr = ["users" => [["name" => "alice"], ["name" => "bob"]]];
array_walk_recursive($arr, function (&$v, $k) { $v = "$k:$v"; });
print_r($arr);

$empty = [];
array_walk($empty, function (&$v) { $v *= 2; });
print_r($empty);

$single = [42];
array_walk($single, function (&$v) { $v = -$v; });
print_r($single);

$arr = [
    "mixed" => [
        "deep" => [1, 2, 3],
        "value" => 42,
    ],
];
array_walk_recursive($arr, function (&$v, $k) { $v *= 10; });
print_r($arr);

$count = 0;
$arr_for_count = [1, [2, 3], [4, [5, 6]]];
array_walk_recursive($arr_for_count, function ($v) use (&$count) { $count++; });
echo $count, "\n";

$nums = [3, 1, 4, 1, 5, 9, 2, 6];
$sum = 0;
array_walk($nums, function ($v) use (&$sum) { $sum += $v; });
echo $sum, "\n";

$names = ["alice", "bob", "carol"];
$result = [];
array_walk($names, function ($name, $i) use (&$result) { $result[$i] = strtoupper($name); });
print_r($result);

class Calculator {
    public int $total = 0;
}
$c = new Calculator;
$nums_for_total = [1, 2, 3, 4];
array_walk($nums_for_total, function ($v) use ($c) { $c->total += $v; });
echo $c->total, "\n";

$tree = ["root" => ["a" => 1, "b" => [2, 3, ["deep" => 4]]]];
$leaves = [];
array_walk_recursive($tree, function ($v) use (&$leaves) { $leaves[] = $v; });
print_r($leaves);

$arr = ["hello", "world"];
$length = 0;
array_walk($arr, function ($s) use (&$length) { $length += strlen($s); });
echo $length, "\n";

$matrix = [[1, 2], [3, 4], [5, 6]];
$flat = [];
array_walk_recursive($matrix, function ($v) use (&$flat) { $flat[] = $v; });
print_r($flat);

$arr = [1, 2, 3];
array_walk($arr, function (&$v, $k) { $v = ["k" => $k, "v" => $v]; });
print_r($arr);

$arr = [["a", "b"], ["c", "d"]];
$walked = [];
array_walk($arr, function ($inner, $i) use (&$walked) {
    foreach ($inner as $j => $v) $walked[] = "$i:$j:$v";
});
print_r($walked);

class StaticHolder {
    public static int $sum = 0;
}
StaticHolder::$sum = 0;
$nums_for_static = [10, 20, 30];
array_walk($nums_for_static, function ($v) { StaticHolder::$sum += $v; });
echo StaticHolder::$sum, "\n";

$counter = [0];
$deep_nums = [1, [2, [3, [4, 5]]]];
array_walk_recursive($deep_nums, function ($v) use (&$counter) { $counter[0]++; });
echo $counter[0], "\n";
