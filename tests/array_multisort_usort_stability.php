<?php
$a = [3, 1, 2];
array_multisort($a);
print_r($a);

$a = [3, 1, 2];
array_multisort($a, SORT_DESC);
print_r($a);

$a = [3, 1, 2];
$b = ["c", "a", "b"];
array_multisort($a, $b);
print_r($a);
print_r($b);

$keys = ["banana", "apple", "cherry"];
$vals = [2, 1, 3];
array_multisort($keys, $vals);
print_r($keys);
print_r($vals);

$a = [3, 1, 2, 1, 2];
$b = ["a", "b", "c", "d", "e"];
array_multisort($a, $b);
print_r($a);
print_r($b);

$a = [3, 1, 2];
array_multisort($a, SORT_NUMERIC);
print_r($a);

$a = ["10", "9", "1", "100"];
array_multisort($a, SORT_NUMERIC);
print_r($a);

$a = ["10", "9", "1", "100"];
array_multisort($a, SORT_STRING);
print_r($a);

$a = ["B", "a", "C", "b"];
array_multisort($a);
print_r($a);

$a = ["B", "a", "C", "b"];
array_multisort($a, SORT_FLAG_CASE | SORT_STRING);
print_r($a);

$prio = [5, 1, 3, 1];
$names = ["d", "a", "c", "b"];
array_multisort($prio, SORT_DESC, $names, SORT_ASC);
print_r($prio);
print_r($names);

$data = [
    ["a", 30, "x"],
    ["b", 20, "y"],
    ["c", 30, "z"],
    ["d", 10, "w"],
];
$cols = [array_column($data, 1), array_column($data, 0)];
array_multisort($cols[0], SORT_ASC, SORT_NUMERIC, $cols[1], SORT_ASC, $data);
foreach ($data as $r) echo $r[0], "/", $r[1], "/", $r[2], "\n";

$arr = ["alpha" => 3, "beta" => 1, "gamma" => 2];
$copy = $arr;
uasort($copy, fn($a, $b) => $a - $b);
print_r($copy);

$arr = ["c" => 1, "a" => 2, "b" => 3];
uksort($arr, fn($a, $b) => strcmp($a, $b));
print_r($arr);

$arr = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
usort($arr, fn($a, $b) => $a - $b);
print_r($arr);

$arr = [["k" => "b", "v" => 1], ["k" => "a", "v" => 2], ["k" => "a", "v" => 1]];
usort($arr, fn($x, $y) => strcmp($x["k"], $y["k"]));
foreach ($arr as $r) echo $r["k"], "=", $r["v"], " ";
echo "\n";

$items = [
    ["name" => "alpha", "rank" => 2],
    ["name" => "beta", "rank" => 1],
    ["name" => "gamma", "rank" => 2],
    ["name" => "delta", "rank" => 1],
];

usort($items, fn($a, $b) => $a["rank"] - $b["rank"]);
foreach ($items as $r) echo $r["name"], "(", $r["rank"], ") ";
echo "\n";

$arr = [[1, "z"], [2, "a"], [1, "a"], [2, "z"], [1, "b"]];
usort($arr, fn($a, $b) => $a[0] - $b[0] ?: strcmp($a[1], $b[1]));
foreach ($arr as $r) echo $r[0], $r[1], " ";
echo "\n";

$a = [3, 1, 2];
$b = ["c", "a", "b"];
$c = [10, 20, 30];
array_multisort($a, $b, $c);
print_r($a);
print_r($b);
print_r($c);

$keys = [3, 1, 2];
array_multisort($keys, SORT_ASC, SORT_NUMERIC);
print_r($keys);

$keys = ["c", "a", "b"];
array_multisort($keys, SORT_DESC, SORT_STRING);
print_r($keys);

$nums = [1.5, 2.5, 1.5, 2.5];
$tags = ["b", "d", "a", "c"];
array_multisort($nums, SORT_ASC, $tags);
print_r($nums);
print_r($tags);
