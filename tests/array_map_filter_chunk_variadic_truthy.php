<?php
print_r(array_map(fn($a, $b) => $a + $b, [1, 2, 3], [10, 20, 30]));
print_r(array_map(fn($a, $b, $c) => $a * $b * $c, [1, 2], [3, 4], [5, 6]));
print_r(array_map(fn($x) => $x * 2, [1, 2, 3]));

print_r(array_map(null, [1, 2, 3], ["a", "b", "c"]));
print_r(array_map(null, [1, 2, 3], ["a", "b"]));
print_r(array_map(null, [1, 2, 3], ["a", "b", "c"], [true, false, true]));

print_r(array_map(fn($a, $b) => $a + $b, [1, 2], [3]));

print_r(array_map(null, []));
print_r(array_map(null, [], []));
print_r(array_map(null, [1, 2]));

print_r(array_map("strtoupper", ["abc", "def"]));
print_r(array_map("strlen", ["a", "bb", "ccc"]));

print_r(array_filter([0, 1, "", "a", null, false, true, "0", []]));
print_r(array_filter([1, 2, 3, 0, 4, 0, 5]));

print_r(array_filter([1, 2, 3, 4], fn($v) => $v % 2 === 0));
print_r(array_filter(["a"=>1, "b"=>0, "c"=>3, "d"=>0]));
print_r(array_filter(["a"=>1, "b"=>2, "c"=>3], fn($v, $k) => $k !== "b", ARRAY_FILTER_USE_BOTH));
print_r(array_filter(["a"=>1, "b"=>2, "c"=>3], fn($k) => $k !== "b", ARRAY_FILTER_USE_KEY));

print_r(array_filter([]));

print_r(array_filter([null, false, 0, ""]));
print_r(array_filter([true, "a", 1, [1]]));

print_r(array_chunk([1, 2, 3, 4, 5], 2));
print_r(array_chunk([1, 2, 3, 4, 5], 2, true));
print_r(array_chunk([1, 2, 3], 10));
print_r(array_chunk([1, 2, 3], 1));
print_r(array_chunk([], 3));

print_r(array_chunk([1, 2, 3, 4, 5, 6, 7], 3, false));
print_r(array_chunk([1, 2, 3, 4, 5, 6, 7], 3, true));

print_r(array_chunk(["a"=>1, "b"=>2, "c"=>3, "d"=>4], 2));
print_r(array_chunk(["a"=>1, "b"=>2, "c"=>3, "d"=>4], 2, true));

try {
    array_chunk([1, 2, 3], 0);
} catch (\ValueError $e) {
    echo "ve\n";
}

try {
    array_chunk([1, 2, 3], -1);
} catch (\ValueError $e) {
    echo "ve\n";
}

print_r(array_chunk([1, 2, 3, 4, 5], 7));

print_r(array_map(fn(...$args) => array_sum($args), [1, 2, 3], [10, 20, 30], [100, 200, 300]));

function sum3(int $a, int $b, int $c): int { return $a + $b + $c; }
print_r(array_map("sum3", [1, 2, 3], [10, 20, 30], [100, 200, 300]));

print_r(array_map(fn($x) => $x * 2, ["a"=>1, "b"=>2, "c"=>3]));

print_r(array_filter([1, "true", null, 0, "false", false], fn($v) => is_string($v)));

print_r(array_filter([1, 2, 3, 4, 5], fn($v) => $v > 3));

$arr = [10, 20, 30];
print_r(array_map(fn($x) => $x * $x, $arr));
print_r($arr);

$nums = range(1, 10);
print_r(array_filter($nums, fn($n) => $n > 5));

print_r(array_chunk(range(1, 10), 4));
print_r(array_chunk(range(1, 10), 4, true));

class Obj {
    public function __construct(public int $val) {}
}

$objects = [new Obj(1), new Obj(2), new Obj(3)];
$values = array_map(fn($o) => $o->val, $objects);
print_r($values);

$filtered = array_filter($objects, fn($o) => $o->val > 1);
$names = array_map(fn($o) => $o->val, $filtered);
print_r($names);

print_r(array_filter(["a"=>1, "b"=>2], fn($v, $k) => false, ARRAY_FILTER_USE_BOTH));
print_r(array_filter(["a"=>1, "b"=>2], fn($v, $k) => true, ARRAY_FILTER_USE_BOTH));

print_r(array_chunk(["a"=>1, "b"=>2, "c"=>3], 100));
print_r(array_chunk(["a"=>1, "b"=>2, "c"=>3], 100, true));

print_r(array_map(strtolower(...), ["A", "B", "C"]));
print_r(array_map(fn($s) => strrev($s), ["abc", "def"]));

$composed = array_map(
    fn($x) => $x * 10,
    array_filter(range(1, 10), fn($n) => $n % 2 === 0)
);
print_r($composed);

$squared_evens = array_map(
    fn($x) => $x * $x,
    array_filter(range(1, 10), fn($n) => $n % 2 === 0)
);
echo array_sum($squared_evens), "\n";
