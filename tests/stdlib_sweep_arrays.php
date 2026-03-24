<?php
// comprehensive array function sweep

// push/pop/shift/unshift
$arr = [1, 2, 3];
array_push($arr, 4, 5);
echo implode(",", $arr) . "\n";
echo array_pop($arr) . "\n";
echo array_shift($arr) . "\n";
array_unshift($arr, 0);
echo implode(",", $arr) . "\n";

// keys/values
$assoc = ["a" => 1, "b" => 2, "c" => 3];
echo implode(",", array_keys($assoc)) . "\n";
echo implode(",", array_values($assoc)) . "\n";

// search
echo var_export(in_array(2, [1, 2, 3]), true) . "\n";
echo var_export(in_array(5, [1, 2, 3]), true) . "\n";
echo var_export(array_key_exists("b", $assoc), true) . "\n";
echo var_export(array_search(2, [10, 20, 30]), true) . "\n";
echo array_search(20, [10, 20, 30]) . "\n";

// merge/combine
$merged = array_merge([1, 2], [3, 4]);
echo implode(",", $merged) . "\n";
$combined = array_combine(["a", "b"], [1, 2]);
echo $combined["a"] . " " . $combined["b"] . "\n";

// slice/splice
echo implode(",", array_slice([1, 2, 3, 4, 5], 1, 3)) . "\n";
$arr2 = [1, 2, 3, 4, 5];
$removed = array_splice($arr2, 1, 2, [20, 30]);
echo implode(",", $arr2) . "\n";
echo implode(",", $removed) . "\n";

// unique/flip/reverse
echo implode(",", array_unique([1, 2, 2, 3, 3, 3])) . "\n";
$flipped = array_flip(["a" => 1, "b" => 2]);
echo $flipped[1] . " " . $flipped[2] . "\n";
echo implode(",", array_reverse([1, 2, 3])) . "\n";

// sort
$s = [3, 1, 4, 1, 5];
sort($s);
echo implode(",", $s) . "\n";
$s2 = [3, 1, 4, 1, 5];
rsort($s2);
echo implode(",", $s2) . "\n";

// ksort
$ks = ["c" => 3, "a" => 1, "b" => 2];
ksort($ks);
echo implode(",", array_keys($ks)) . "\n";

// usort
$us = [3, 1, 4, 1, 5];
usort($us, function($a, $b) { return $a - $b; });
echo implode(",", $us) . "\n";

// map/filter/reduce
$mapped = array_map(function($x) { return $x * 2; }, [1, 2, 3]);
echo implode(",", $mapped) . "\n";

$filtered = array_filter([1, 2, 3, 4, 5], function($x) { return $x > 2; });
echo implode(",", $filtered) . "\n";

$sum = array_reduce([1, 2, 3, 4], function($carry, $item) { return $carry + $item; }, 0);
echo $sum . "\n";

// chunk/pad/fill
$chunks = array_chunk([1, 2, 3, 4, 5], 2);
echo count($chunks) . "\n";
echo implode(",", $chunks[0]) . "\n";
echo implode(",", $chunks[2]) . "\n";

echo implode(",", array_pad([1, 2], 5, 0)) . "\n";
echo implode(",", array_fill(0, 3, "x")) . "\n";

$fk = array_fill_keys(["a", "b", "c"], 0);
echo $fk["a"] . " " . $fk["b"] . " " . $fk["c"] . "\n";

// column
$records = [
    ["name" => "Alice", "age" => 30],
    ["name" => "Bob", "age" => 25],
    ["name" => "Charlie", "age" => 35],
];
echo implode(",", array_column($records, "name")) . "\n";

// intersect/diff
echo implode(",", array_intersect([1, 2, 3, 4], [2, 4, 6])) . "\n";
echo implode(",", array_diff([1, 2, 3, 4], [2, 4, 6])) . "\n";

// sum/product
echo array_sum([1, 2, 3, 4]) . "\n";
echo array_product([1, 2, 3, 4]) . "\n";

// count_values
$cv = array_count_values(["a", "b", "a", "c", "b", "a"]);
echo $cv["a"] . " " . $cv["b"] . " " . $cv["c"] . "\n";

// range
echo implode(",", range(1, 5)) . "\n";
echo implode(",", range(0, 10, 3)) . "\n";

// key functions
echo array_key_first(["x" => 1, "y" => 2]) . "\n";
echo array_key_last(["x" => 1, "y" => 2]) . "\n";

// array_walk
$walked = ["a" => 1, "b" => 2, "c" => 3];
$walk_output = "";
array_walk($walked, function($val, $key) { echo $key; });
echo "\n";

// array_replace
$replaced = array_replace([1, 2, 3], [0 => 10, 2 => 30]);
echo implode(",", $replaced) . "\n";

// compact/extract
$name = "Alice";
$age = 30;
$data = compact("name", "age");
echo $data["name"] . " " . $data["age"] . "\n";

// array_any/array_all (PHP 8.4)
echo var_export(array_any([1, 2, 3], function($v) { return $v > 2; }), true) . "\n";
echo var_export(array_all([1, 2, 3], function($v) { return $v > 0; }), true) . "\n";
echo var_export(array_all([1, 2, 3], function($v) { return $v > 2; }), true) . "\n";

echo "done\n";
