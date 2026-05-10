<?php
// sort - reindexes
$a = [3, 1, 4, 1, 5, 9, 2, 6];
sort($a);
print_r($a);

// rsort
$a = [3, 1, 4, 1, 5];
rsort($a);
print_r($a);

// asort - preserves keys, ascending
$a = ["c" => 3, "a" => 1, "b" => 2];
asort($a);
print_r($a);

// arsort
$a = ["a" => 1, "b" => 3, "c" => 2];
arsort($a);
print_r($a);

// ksort - sort by key
$a = ["c" => 3, "a" => 1, "b" => 2];
ksort($a);
print_r($a);

// krsort
krsort($a);
print_r($a);

// usort - custom compare, reindexes
$a = [3, 1, 4, 1, 5];
usort($a, fn($x, $y) => $x - $y);
print_r($a);

// usort with objects
class Item { public function __construct(public int $n) {} }
$items = [new Item(3), new Item(1), new Item(2)];
usort($items, fn($a, $b) => $a->n - $b->n);
foreach ($items as $i) echo $i->n, " ";
echo "\n";

// uasort - preserves keys
$a = ["c" => 3, "a" => 1, "b" => 2];
uasort($a, fn($x, $y) => $x - $y);
print_r($a);

// uksort
$a = ["x_3" => "c", "y_1" => "a", "z_2" => "b"];
uksort($a, fn($x, $y) => substr($x, 2) <=> substr($y, 2));
print_r($a);

// natsort
$a = ["img10", "img2", "img1", "img12"];
natsort($a);
print_r($a);

// natcasesort
$a = ["IMG10", "img2", "Img1"];
natcasesort($a);
print_r($a);

// SORT_FLAGS for sort
$a = ["10", "2", "1", "20"];
sort($a, SORT_STRING);
print_r($a);

$a = ["10", "2", "1", "20"];
sort($a, SORT_NUMERIC);
print_r($a);

$a = ["img10", "img2", "img1"];
sort($a, SORT_NATURAL);
print_r($a);

$a = ["IMG10", "img2", "Img1"];
sort($a, SORT_NATURAL | SORT_FLAG_CASE);
print_r($a);

// stable sort: equal-valued elements maintain relative order
$a = [
    ["n" => 1, "id" => "a"],
    ["n" => 2, "id" => "b"],
    ["n" => 1, "id" => "c"],
    ["n" => 2, "id" => "d"],
];
usort($a, fn($x, $y) => $x["n"] <=> $y["n"]);
foreach ($a as $r) echo $r["id"], " ";
echo "\n";

// array_multisort
$a = [3, 1, 4];
$b = ["x", "y", "z"];
array_multisort($a, $b);
print_r($a);
print_r($b);

// array_multisort with direction
$a = [3, 1, 4];
$b = ["x", "y", "z"];
array_multisort($a, SORT_DESC, $b);
print_r($a);
print_r($b);

// shuffle - just verify count
$a = [1, 2, 3, 4, 5];
shuffle($a);
echo count($a), " ", in_array(3, $a) ? "has-3" : "no-3", "\n";

// array_reverse
print_r(array_reverse([1, 2, 3]));
print_r(array_reverse(["a", "b", "c"], true));

// in_array strict
$a = [0, 1, "1", true];
var_dump(in_array(1, $a));
var_dump(in_array(1, $a, true));
var_dump(in_array("0", $a));
var_dump(in_array("0", $a, true));

// array_search
var_dump(array_search(3, [1, 2, 3, 2, 1]));
var_dump(array_search("xyz", ["a", "b", "c"]));

// array_unique
print_r(array_unique([1, 2, 2, 3, 1]));
print_r(array_unique(["a", "b", "a", "c"]));
print_r(array_unique([1, "1", 2], SORT_STRING));
print_r(array_unique([1, "1", 2], SORT_NUMERIC));

// array_count_values
print_r(array_count_values(["a", "b", "a", "c", "b", "a"]));

// usort returns true
$a = [3, 1, 2];
$r = usort($a, fn($x, $y) => $x - $y);
var_dump($r);
print_r($a);

// sort returns true
$a = [3, 1, 2];
$r = sort($a);
var_dump($r);

// usort with stable equal keys
$a = [["n"=>1,"k"=>"a"], ["n"=>1,"k"=>"b"]];
usort($a, fn($x,$y) => 0); // all equal
foreach ($a as $r) echo $r["k"], " ";
echo "\n";

// sort empty
$a = [];
sort($a);
print_r($a);
