<?php
$a = [3, 1, 4, 1, 5, 9, 2, 6];
sort($a); print_r($a);
rsort($a); print_r($a);

$a = ["b" => 2, "a" => 1, "c" => 3];
asort($a); print_r($a);
$a = ["b" => 2, "a" => 1, "c" => 3];
arsort($a); print_r($a);
$a = ["b" => 2, "a" => 1, "c" => 3];
ksort($a); print_r($a);
$a = ["b" => 2, "a" => 1, "c" => 3];
krsort($a); print_r($a);

$a = [10, 1, 2, 20, 3];
usort($a, fn($x, $y) => $x - $y); print_r($a);

$a = ["a" => 3, "b" => 1, "c" => 2];
uasort($a, fn($x, $y) => $x - $y); print_r($a);

$a = ["b" => 1, "a" => 2, "c" => 3];
uksort($a, fn($x, $y) => strcmp($x, $y)); print_r($a);

$a = ["item20", "item3", "item1", "item10"];
natsort($a); print_r($a);
$a = ["Item20", "item3", "ITEM1", "Item10"];
natcasesort($a); print_r($a);

$a = [10, "2", 1, "20"];
sort($a); print_r($a);
$a = [10, "2", 1, "20"];
sort($a, SORT_STRING); print_r($a);
$a = [10, "2", 1, "20"];
sort($a, SORT_NUMERIC); print_r($a);

$a = ["img10", "img2", "img1"];
sort($a, SORT_NATURAL); print_r($a);
$a = ["IMG10", "img2", "Img1"];
sort($a, SORT_NATURAL | SORT_FLAG_CASE); print_r($a);

$items = [
    ["name" => "alice", "age" => 30],
    ["name" => "bob", "age" => 25],
    ["name" => "carol", "age" => 35],
];
usort($items, fn($a, $b) => $a["age"] <=> $b["age"]);
foreach ($items as $it) echo $it["name"], " ", $it["age"], "\n";

$a = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
$b = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
array_multisort($a, $b);
print_r($a); print_r($b);

$names = ["alice", "bob", "carol"];
$ages = [30, 25, 35];
array_multisort($ages, $names);
print_r($ages); print_r($names);

$data = [3, 1, 4, 1, 5, 9, 2, 6];
array_multisort($data, SORT_DESC);
print_r($data);

$d1 = [3, 1, 2];
$d2 = ["c", "a", "b"];
$d3 = [30, 10, 20];
array_multisort($d1, $d2, $d3);
print_r($d1); print_r($d2); print_r($d3);

$a = [3.14, 1.5, 2.71];
sort($a); print_r($a);

$a = [];
sort($a); echo count($a), "\n";

$objs = [(object)["v" => 3], (object)["v" => 1], (object)["v" => 2]];
usort($objs, fn($a, $b) => $a->v - $b->v);
foreach ($objs as $o) echo $o->v, " "; echo "\n";

$stable = [
    ["key" => "a", "val" => 1],
    ["key" => "a", "val" => 2],
    ["key" => "a", "val" => 3],
    ["key" => "b", "val" => 4],
];
usort($stable, fn($x, $y) => strcmp($x["key"], $y["key"]));
foreach ($stable as $s) echo $s["val"], " "; echo "\n";
