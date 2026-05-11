<?php
$arr = [1, 2, 3];
echo array_pop($arr), "\n";
print_r($arr);
echo count($arr), "\n";

$arr = [];
echo var_export(array_pop($arr), true), "\n";
print_r($arr);

$arr = [1, 2, 3];
echo array_shift($arr), "\n";
print_r($arr);

$arr = ["a"=>1, "b"=>2, "c"=>3];
echo array_pop($arr), "\n";
print_r($arr);

$arr = ["a"=>1, "b"=>2, "c"=>3];
echo array_shift($arr), "\n";
print_r($arr);

$arr = [];
echo var_export(array_shift($arr), true), "\n";

$arr = ["only"];
echo array_pop($arr), "\n";
echo count($arr), "\n";
echo var_export(array_pop($arr), true), "\n";

$arr = [];
echo array_push($arr, 1, 2, 3), "\n";
print_r($arr);

$arr = [10];
echo array_push($arr, 20, 30), "\n";
print_r($arr);

$arr = [];
echo array_unshift($arr, 1, 2, 3), "\n";
print_r($arr);

$arr = [10];
echo array_unshift($arr, 1, 2, 3), "\n";
print_r($arr);

$arr = ["a"=>1, "b"=>2];
echo array_push($arr, 99), "\n";
print_r($arr);

$arr = ["a"=>1, "b"=>2];
echo array_unshift($arr, 99), "\n";
print_r($arr);

print_r(array_reverse([1, 2, 3, 4]));
print_r(array_reverse([1, 2, 3, 4], true));
print_r(array_reverse(["a"=>1, "b"=>2, "c"=>3]));
print_r(array_reverse(["a"=>1, "b"=>2, "c"=>3], true));
print_r(array_reverse([5=>"a", 10=>"b", 15=>"c"]));
print_r(array_reverse([5=>"a", 10=>"b", 15=>"c"], true));
print_r(array_reverse([]));
print_r(array_reverse([42]));

$mixed = [0=>"a", "k"=>"b", 1=>"c"];
print_r(array_reverse($mixed));
print_r(array_reverse($mixed, true));

$arr = [];
for ($i = 0; $i < 10; $i++) array_push($arr, $i);
echo count($arr), "\n";
echo array_sum($arr), "\n";

$arr = [];
while (count($arr) < 5) array_unshift($arr, count($arr));
print_r($arr);

$stack = [];
array_push($stack, "a");
array_push($stack, "b");
array_push($stack, "c");
echo array_pop($stack), array_pop($stack), array_pop($stack), "\n";
echo count($stack), "\n";

$queue = [];
array_push($queue, "a");
array_push($queue, "b");
array_push($queue, "c");
echo array_shift($queue), array_shift($queue), array_shift($queue), "\n";
echo count($queue), "\n";

$arr = ["a"=>1, "b"=>2];
$popped = array_pop($arr);
echo $popped, "\n";
print_r($arr);

$arr = [1, 2, 3];
$out = [];
while (!empty($arr)) $out[] = array_pop($arr);
print_r($out);

$arr = ["x", "y", "z"];
$top = array_pop($arr);
echo $top, "\n";
$arr[] = "w";
print_r($arr);

$arr = [1, 2, 3];
echo array_push($arr) === 3 ? "y" : "n", "\n";

$arr = [];
echo array_unshift($arr) === 0 ? "y" : "n", "\n";

$nums = [1, 2, 3];
print_r(array_reverse($nums));
print_r($nums);

$keys = [10 => "a", 20 => "b", 30 => "c"];
print_r(array_reverse($keys));
print_r(array_reverse($keys, true));

$bool_arr = [true, false, true, false];
print_r(array_reverse($bool_arr));

$nested = [[1, 2], [3, 4]];
print_r(array_reverse($nested));

print_r(array_reverse(range(1, 5)));

$arr = [1, 2, 3];
echo array_push($arr, ...[10, 20]), "\n";
print_r($arr);

$arr = [];
echo array_push($arr, ...[1, 2, 3]), "\n";
print_r($arr);

$copy = [1, 2, 3];
$x = array_pop($copy);
$y = array_pop($copy);
echo $x, " ", $y, "\n";
print_r($copy);

$arr = ["k" => 1];
echo array_pop($arr), "\n";
print_r($arr);

$arr = [];
$null = array_pop($arr);
echo $null === null ? "y" : "n", "\n";

$arr = [];
$null = array_shift($arr);
echo $null === null ? "y" : "n", "\n";

$arr = [1.5, 2.5, 3.5];
echo array_pop($arr), "\n";

$arr = ["a"];
echo array_pop($arr), "\n";

print_r(array_reverse(["one" => 1, 0 => "two", "three" => 3]));
print_r(array_reverse(["one" => 1, 0 => "two", "three" => 3], true));
