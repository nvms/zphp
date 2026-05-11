<?php
$a = [3, 1, 2];
sort($a);
print_r($a);

$a = [3, 1, 2];
rsort($a);
print_r($a);

$a = ["c" => 3, "a" => 1, "b" => 2];
asort($a);
print_r($a);

$a = ["c" => 3, "a" => 1, "b" => 2];
arsort($a);
print_r($a);

$a = ["c" => 3, "a" => 1, "b" => 2];
ksort($a);
print_r($a);

$a = ["c" => 3, "a" => 1, "b" => 2];
krsort($a);
print_r($a);

$a = ["item10", "item2", "item1"];
sort($a, SORT_NATURAL);
print_r($a);

$a = ["item10", "item2", "item1"];
sort($a, SORT_NATURAL | SORT_FLAG_CASE);
print_r($a);

$a = ["item10", "ITEM2", "item1"];
sort($a, SORT_NATURAL);
print_r($a);

$a = ["item10", "ITEM2", "item1"];
sort($a, SORT_NATURAL | SORT_FLAG_CASE);
print_r($a);

$a = ["b", "B", "a", "A", "c", "C"];
sort($a);
print_r($a);

$a = ["b", "B", "a", "A", "c", "C"];
sort($a, SORT_STRING);
print_r($a);

$a = ["b", "B", "a", "A", "c", "C"];
sort($a, SORT_STRING | SORT_FLAG_CASE);
print_r($a);

$a = ["1", "10", "2"];
sort($a, SORT_NUMERIC);
print_r($a);

$a = ["1", "10", "2"];
sort($a, SORT_STRING);
print_r($a);

$a = ["1", "10", "2"];
sort($a, SORT_NATURAL);
print_r($a);

$a = [1, "2", 3.0, "hello"];
sort($a);
print_r($a);

$a = ["foo10", "foo2", "foo1"];
natsort($a);
print_r($a);

$a = ["foo10", "FOO2", "foo1"];
natcasesort($a);
print_r($a);

$nums = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
usort($nums, fn($x, $y) => $x - $y);
print_r($nums);

$nums = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
usort($nums, fn($x, $y) => $y - $x);
print_r($nums);

$pairs = [["a", 1], ["b", 0], ["a", 0]];
usort($pairs, fn($x, $y) => $x[0] <=> $y[0] ?: $x[1] <=> $y[1]);
print_r($pairs);

$arr = [3, 1, 2];
uasort($arr, fn($a, $b) => $a - $b);
print_r($arr);

$arr = ["c" => 3, "a" => 1, "b" => 2];
uksort($arr, fn($a, $b) => strcmp($a, $b));
print_r($arr);

$emp = [];
sort($emp);
print_r($emp);

$one = [42];
sort($one);
print_r($one);

$dup = [2, 2, 1, 1];
sort($dup);
print_r($dup);

$mixed = [10, "10", "abc", 5];
sort($mixed);
print_r($mixed);

$mixed = [10, "10", "abc", 5];
sort($mixed, SORT_STRING);
print_r($mixed);

$arr = [1.5, 2.5, 1.5];
sort($arr);
print_r($arr);

$bool = [true, false, true, false];
sort($bool);
print_r($bool);

$negatives = [-1, -10, -2];
sort($negatives);
print_r($negatives);

$a = ["A10", "a2", "B1", "b3"];
sort($a, SORT_NATURAL | SORT_FLAG_CASE);
print_r($a);

$a = [10, 5, 100, 1];
rsort($a, SORT_NUMERIC);
print_r($a);

$keys = ["10" => "a", "2" => "b", "1" => "c"];
ksort($keys, SORT_NUMERIC);
print_r($keys);

$keys = ["10" => "a", "2" => "b", "1" => "c"];
ksort($keys, SORT_STRING);
print_r($keys);

$arr = [3, 1, 2];
$copy = $arr;
asort($arr);
print_r($arr);
print_r($copy);
