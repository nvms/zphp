<?php
// array_filter with ARRAY_FILTER_USE_KEY
$a = ["a" => 1, "b" => 2, "c" => 3, "d" => 4];
print_r(array_filter($a, fn($k) => in_array($k, ["a", "c"]), ARRAY_FILTER_USE_KEY));
print_r(array_filter([1, 2, 3, 4, 5], fn($k) => $k % 2 == 0, ARRAY_FILTER_USE_KEY));
print_r(array_filter([1, 2, 3], fn() => true)); // no flag
print_r(array_filter([])); // empty

// array_map preserve string keys with single arg
print_r(array_map(fn($v) => $v * 10, ["a" => 1, "b" => 2, "c" => 3]));
// array_map with multiple arrays - keys NOT preserved (renumbered)
print_r(array_map(fn($x, $y) => "$x:$y", ["a" => 1, "b" => 2], ["x" => 10, "y" => 20]));

// array_keys with search
print_r(array_keys(["a" => 1, "b" => 2, "c" => 1], 1));
print_r(array_keys([1, 2, 3, 2, 1], 1));
// strict
print_r(array_keys(["a" => 1, "b" => "1", "c" => 1.0], 1, true));

// array_values
print_r(array_values(["a" => 1, "b" => 2, "c" => 3]));
print_r(array_values([5 => "x", 10 => "y", 99 => "z"]));

// array_unique preserves keys
print_r(array_unique(["a" => 1, "b" => 1, "c" => 2, "d" => 3, "e" => 2]));
print_r(array_unique([3, 1, 4, 1, 5, 9, 2, 6, 5, 3]));

// sort/rsort with SORT_FLAG_CASE
$a = ["B", "a", "C", "b", "A"];
sort($a, SORT_STRING | SORT_FLAG_CASE);
print_r($a);
$a = ["BAR", "foo", "Bar", "FOO"];
sort($a, SORT_STRING | SORT_FLAG_CASE);
print_r($a);
$a = ["BAR", "foo", "Bar", "FOO"];
rsort($a, SORT_STRING | SORT_FLAG_CASE);
print_r($a);

// natsort
$a = ["img12", "img10", "img1", "img2"];
natsort($a);
print_r($a);
$a = ["IMG10", "img2", "IMG1", "img11"];
natcasesort($a);
print_r($a);

// array_pop/array_push
$a = [1, 2, 3];
$last = array_pop($a);
echo "popped=$last left=" . count($a) . "\n";
print_r($a);

$len = array_push($a, 10, 20, 30);
echo "len=$len\n";
print_r($a);

// array_shift/array_unshift
$a = [1, 2, 3];
$first = array_shift($a);
echo "shifted=$first\n";
print_r($a); // [2, 3]

$len = array_unshift($a, 0, -1);
echo "ulen=$len\n";
print_r($a); // [0, -1, 2, 3]

// numeric keys preserved on shift?
$a = [5 => "a", 10 => "b", 99 => "c"];
$f = array_shift($a);
echo "shifted-assoc=$f\n";
print_r($a);

// pop on empty
$a = [];
$x = array_pop($a);
var_dump($x);
$y = array_shift($a);
var_dump($y);

// current/key/next/prev/reset/end on empty
$a = [];
var_dump(current($a));
var_dump(key($a));
var_dump(next($a));
var_dump(prev($a));
var_dump(reset($a));
var_dump(end($a));

// array_replace vs array_merge with numeric keys
$a = [1, 2, 3];
$b = [10, 20];
print_r(array_replace($a, $b)); // [10, 20, 3]
print_r(array_merge($a, $b)); // [1, 2, 3, 10, 20]
print_r(array_replace([5 => "a", 10 => "b"], [5 => "X"])); // {5: "X", 10: "b"}

// spread with associative
$a = ["a" => 1, "b" => 2];
$b = ["c" => 3];
print_r([...$a, ...$b]);
print_r([...$a, "a" => 99]);

// list/array destructure shorter than expected - PHP emits Undefined-key notice
@(
$arr_pair = [1, 2]
);
$x = $arr_pair[0]; $y = $arr_pair[1]; $z = @$arr_pair[2];
echo "$x $y "; var_dump($z);

// array_pad with non-empty
print_r(array_pad([1, 2, 3], 5, 0));
print_r(array_pad([1, 2, 3], -5, 0));
print_r(array_pad(["a" => 1], 3, 0));

// array_walk with extra
$a = [1, 2, 3];
array_walk($a, function(&$v, $k, $extra) { $v = "$k+$extra=$v"; }, 100);
print_r($a);
