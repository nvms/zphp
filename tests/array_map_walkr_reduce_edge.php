<?php
print_r(array_map(fn($a, $b, $c) => $a + $b + $c, [1, 2, 3], [10, 20, 30], [100, 200, 300]));

print_r(array_map(fn($a, $b, $c, $d) => "$a-$b-$c-$d", [1, 2], ["a", "b"], [true, false], [10.5, 20.5]));

print_r(array_map(null, [1, 2, 3], [10, 20, 30], [100, 200, 300]));

print_r(array_map(null, [1, 2], [10, 20, 30, 40]));

print_r(array_map(fn(...$xs) => array_sum($xs), [1, 2], [10, 20], [100, 200], [1000, 2000]));

print_r(array_map("max", [1, 2, 3], [3, 2, 1]));
print_r(array_map("min", [1, 2, 3], [3, 2, 1]));

$arr = [1, [2, 3, [4, [5, 6]]], 7];
$out = [];
array_walk_recursive($arr, function ($v) use (&$out) {
    $out[] = $v;
});
print_r($out);

$arr = [
    "a" => 1,
    "b" => [
        "c" => 2,
        "d" => ["e" => 3, "f" => 4],
    ],
    "g" => 5,
];
$keys = [];
array_walk_recursive($arr, function ($v, $k) use (&$keys) {
    $keys[] = $k;
});
print_r($keys);

$arr = ["a" => 1, "b" => "str", "c" => 2.5, "d" => [1, "x", true]];
$types = [];
array_walk_recursive($arr, function ($v) use (&$types) {
    $types[] = gettype($v);
});
print_r($types);

$arr = [];
$count = 0;
array_walk_recursive($arr, function () use (&$count) { $count++; });
echo "empty=", $count, "\n";

$arr = [[[]]];
$count = 0;
array_walk_recursive($arr, function () use (&$count) { $count++; });
echo "nested-empty=", $count, "\n";

echo array_reduce([1, 2, 3, 4, 5], fn($c, $v) => $c + $v, 0), "\n";
echo array_reduce([1, 2, 3, 4, 5], fn($c, $v) => $c + $v, 100), "\n";

echo array_reduce([1], fn($c, $v) => $c + $v, 0), "\n";
echo array_reduce([1], fn($c, $v) => $c + $v, 100), "\n";

$r = array_reduce([], fn($c, $v) => $c + $v, 0);
var_dump($r);

$r = array_reduce([], fn($c, $v) => $c + $v);
var_dump($r);

$r = array_reduce([1, 2, 3], fn($c, $v) => $c + $v);
var_dump($r);

$r = array_reduce([1], fn($c, $v) => $c + $v);
var_dump($r);

echo array_reduce([1, 2, 3, 4], fn($c, $v) => $c . "/" . $v, ""), "\n";

// array_reduce with non-numeric initial + int op (architectural - PHP TypeError, zphp permissive)

class Item { public function __construct(public int $n) {} }
$objs = [new Item(1), new Item(2), new Item(3)];
$sum = array_reduce($objs, fn($c, Item $i) => $c + $i->n, 0);
echo $sum, "\n";

$max = array_reduce($objs, fn(?Item $c, Item $i) => $c === null ? $i : ($i->n > $c->n ? $i : $c));
echo $max->n, "\n";

$result = array_reduce(
    [["a" => 1], ["b" => 2], ["c" => 3]],
    fn($c, $v) => array_merge($c, $v),
    [],
);
print_r($result);

$flatten = array_reduce(
    [[1, 2], [3, 4], [5]],
    fn($c, $v) => array_merge($c, $v),
    [],
);
print_r($flatten);

$lookup = array_reduce(
    [["k" => "a", "v" => 1], ["k" => "b", "v" => 2]],
    fn($c, $r) => array_merge($c, [$r["k"] => $r["v"]]),
    [],
);
print_r($lookup);

print_r(array_map(fn($a, $b, $c) => [$a, $b, $c], [1, 2, 3], ["a", "b", "c"], [true, false, true]));

$result = array_map(
    fn(int $a, int $b, int $c, int $d, int $e) => $a + $b + $c + $d + $e,
    [1, 2], [10, 20], [100, 200], [1000, 2000], [10000, 20000]
);
print_r($result);

print_r(array_map(null, [1, 2], [3, 4]));

$first_only = array_map(null, [1, 2, 3]);
print_r($first_only);

$arr = [
    "level1" => [
        "level2" => [
            "level3" => "deep",
        ],
    ],
    "shallow" => "top",
];
$collected = [];
array_walk_recursive($arr, function ($v, $k) use (&$collected) {
    $collected["$k"] = $v;
});
print_r($collected);

$inputs = [
    [1, 2],
    [10, 20],
    [100, 200],
];
$result = array_reduce($inputs, function ($carry, $row) {
    return array_map(fn($a, $b) => $a + $b, $carry, $row);
}, [0, 0]);
print_r($result);
