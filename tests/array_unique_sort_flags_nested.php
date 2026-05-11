<?php
print_r(array_unique([1, 2, 2, 3, 3, 3, 4]));
print_r(array_unique(["a", "b", "a", "c"]));
print_r(array_unique([1, "1", 1.0, true]));
print_r(array_unique([]));
print_r(array_unique(["only"]));

print_r(array_unique([1, 2, 3, 4], SORT_REGULAR));
print_r(array_unique([1, 2, 3, 4], SORT_NUMERIC));
print_r(array_unique([1, 2, 3, 4], SORT_STRING));

print_r(array_unique([10, "10", 10.0], SORT_REGULAR));
print_r(array_unique([10, "10", 10.0], SORT_STRING));
print_r(array_unique([10, "10", 10.0], SORT_NUMERIC));

print_r(array_unique(["banana", "apple", "banana", "cherry"]));

print_r(array_unique(["a" => 1, "b" => 2, "c" => 1, "d" => 2]));

print_r(array_unique([1, 2, 1, 3, 2, 4, 3, 5]));

print_r(array_unique([1.5, 2.5, 1.5, 3.5]));

print_r(array_unique(["a", "A", "b", "B"]));
print_r(array_unique(["a", "A", "b", "B"], SORT_STRING | SORT_FLAG_CASE));

$arr = ["x" => 1, "y" => 2, "z" => 1];
$u = array_unique($arr);
print_r($u);

$nested = [[1, 2], [3, 4], [1, 2]];
print_r(array_unique($nested, SORT_REGULAR));

$mix = [0, "0", false, true];
print_r(array_unique($mix));
print_r(array_unique($mix, SORT_REGULAR));

print_r(array_unique([10, 2, 100, 20, 200, 2]));
print_r(array_unique([10, 2, 100, 20, 200, 2], SORT_NUMERIC));
print_r(array_unique([10, 2, 100, 20, 200, 2], SORT_STRING));

$a = new stdClass; $a->id = 1;
$b = new stdClass; $b->id = 2;
$c = new stdClass; $c->id = 1;
try {
    print_r(array_unique([$a, $b, $c], SORT_REGULAR));
} catch (\Throwable $e) {
    echo get_class($e), "\n";
}

print_r(array_unique([1, "1.0", 1.0], SORT_REGULAR));

print_r(array_unique(["foo bar", "foo bar", "Foo Bar"]));

print_r(array_unique([1, "1", "01", "1.0", 1.0]));

print_r(array_unique(["item1", "item10", "item2"], SORT_NATURAL));
print_r(array_unique(["ITEM1", "item1"], SORT_NATURAL | SORT_FLAG_CASE));

$arr = ["x" => 1, "y" => 1, "z" => 2];
$u = array_unique($arr);
echo count($u), "\n";
$keys = array_keys($u);
print_r($keys);

$arr = [1.1, 1.10, 1.100];
print_r(array_unique($arr));

$arr = [INF, INF, -INF, -INF];
print_r(array_unique($arr));

$arr = [["a"], ["b"], ["a"]];
print_r(array_unique($arr, SORT_REGULAR));

$repeated = array_fill(0, 100, "x");
$repeated[] = "y";
echo count(array_unique($repeated)), "\n";

$nums = range(1, 10);
$dups = array_merge($nums, $nums);
echo count(array_unique($dups)), "\n";

$arr = ["abc", "abc", "ABC", "abc"];
print_r(array_unique($arr));
print_r(array_unique($arr, SORT_STRING));

$arr = [true, true, false, false, true];
print_r(array_unique($arr));

$arr = [null, null, 0, 0];
print_r(array_unique($arr));
print_r(array_unique($arr, SORT_REGULAR));

$arr = ["alpha", "beta", "alpha", "gamma", "beta"];
$u = array_unique($arr);
echo count($u), "\n";
echo implode(",", $u), "\n";
