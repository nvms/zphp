<?php
$nested = [1, [2, 3, [4, 5]], 6];
array_walk_recursive($nested, function (&$v, $k) { $v *= 10; });
print_r($nested);

$nested = ["a" => 1, "b" => ["c" => 2, "d" => 3], "e" => [4]];
array_walk_recursive($nested, function (&$v, $k) { $v = $k . ":" . $v; });
print_r($nested);

$nested = [[1,2],[3,4]];
array_walk_recursive($nested, function (&$v, $k, $extra) { $v += $extra; }, 100);
print_r($nested);

$arr = [["a" => 1, "b" => 2], ["a" => 3, "b" => 4]];
array_walk_recursive($arr, function (&$v, $k, $mult) { $v *= $mult; }, 2);
print_r($arr);

print_r(array_map(null, [1,2,3], ["a","b","c"]));
print_r(array_map(null, [1,2,3], ["a","b","c"], [true,false,true]));
print_r(array_map(null, [1,2,3], [4,5]));
print_r(array_map(null, [1,2,3]));
print_r(array_map(null, []));
print_r(array_map(null, [1,2], [3,4], [5,6]));

print_r(array_map(fn($a, $b) => $a * $b, [1,2,3], [10,20,30]));
print_r(array_map(fn($a, $b, $c) => "$a-$b-$c", ["x","y"], [1,2], [true,false]));
print_r(array_map("strtoupper", ["foo","bar"]));
print_r(array_map(null, ["x"=>1,"y"=>2], ["a","b"]));

print_r(array_filter(["a"=>1,"b"=>0,"c"=>2,"d"=>null,"e"=>"","f"=>3]));
print_r(array_filter([1,2,3,4,5], fn($v) => $v > 2));
print_r(array_filter(["a"=>1,"b"=>2,"c"=>3], fn($k) => $k !== "b", ARRAY_FILTER_USE_KEY));
print_r(array_filter(["a"=>1,"b"=>2,"c"=>3], fn($v, $k) => $v > 1 && $k !== "c", ARRAY_FILTER_USE_BOTH));
print_r(array_filter([0, false, null, "", "0", "x"]));
print_r(array_filter(["k"=>0, 5, 0, "x"], fn($v) => true));
print_r(array_filter([], fn($v) => $v > 0));

echo array_reduce([1,2,3,4], fn($c, $i) => $c + $i, 0), "\n";
echo array_reduce([1,2,3,4], fn($c, $i) => $c + $i), "\n";
echo var_export(array_reduce([], fn($c, $i) => $c + $i), true), "\n";
echo array_reduce([], fn($c, $i) => $c + $i, 100), "\n";

$r = array_reduce([1,2,3], fn($c, $i) => array_merge($c, [$i*2]), []);
print_r($r);

$r = array_reduce(["a","b","c"], fn($c, $i) => $c . "-" . $i, "");
echo $r, "\n";

$r = array_reduce([1,2,3], fn($c, $i) => $c === null ? $i : $c * $i, null);
echo $r, "\n";

$r = array_reduce([[1,2],[3,4],[5,6]], fn($c, $i) => array_merge($c, $i), []);
print_r($r);

echo array_reduce([1,2,3,4,5], fn($c, $i) => $c + $i, 10), "\n";

$r = array_reduce(["x","y","z"], function ($c, $i) {
    $c[$i] = strlen($i) + count($c);
    return $c;
}, []);
print_r($r);

$arr = [["x"=>1,"y"=>2],["x"=>3,"y"=>4]];
array_walk_recursive($arr, function (&$v) { $v++; });
print_r($arr);

$keys = ["a","b","c"];
$vals = [1,2,3];
print_r(array_map(null, $keys, $vals));

$nums = [1,2,3,4,5];
$factor = 10;
print_r(array_map(fn($n) => $n * $factor, $nums));

print_r(array_filter([1,2,3,4,5,6,7,8], fn($v) => $v % 2 === 0));
print_r(array_filter(["x"=>1,"y"=>0,"z"=>3]));

$max = array_reduce([3,1,4,1,5,9,2,6], fn($c, $i) => $i > $c ? $i : $c, PHP_INT_MIN);
echo $max, "\n";
