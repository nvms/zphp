<?php
// array_walk_recursive callback signature
$arr = ["a" => 1, "b" => ["c" => 2, "d" => 3], "e" => 4];
$out = [];
array_walk_recursive($arr, function ($v, $k) use (&$out) {
    $out[] = "$k=$v";
});
print_r($out);

// with extra arg via use
$mul = 10;
$arr = [1, 2, [3, 4, [5]]];
array_walk_recursive($arr, function (&$v, $k) use ($mul) {
    $v = $v * $mul;
});
print_r($arr);

// array_walk_recursive with userdata (4th arg)
$arr = [1, 2, [3, 4]];
array_walk_recursive($arr, function (&$v, $k, $multiplier) {
    $v *= $multiplier;
}, 100);
print_r($arr);

// array_walk callback by-reference
$arr = [1, 2, 3];
array_walk($arr, function (&$v, $k) { $v = $v + 100; });
print_r($arr);

// array_walk with userdata
$arr = [1, 2, 3];
array_walk($arr, function (&$v, $k, $extra) { $v += $extra; }, 50);
print_r($arr);

// array_filter default (truthy)
print_r(array_filter([0, 1, 2, "", "x", null, false, "0", " "]));

// array_filter with callback (no flag)
print_r(array_filter([1, 2, 3, 4, 5], fn($v) => $v % 2 === 0));

// array_filter ARRAY_FILTER_USE_KEY
$arr = ["a" => 1, "b" => 2, "c" => 3];
print_r(array_filter($arr, fn($k) => $k !== "b", ARRAY_FILTER_USE_KEY));

// array_filter ARRAY_FILTER_USE_BOTH
print_r(array_filter($arr, fn($v, $k) => $v > 1 && $k !== "c", ARRAY_FILTER_USE_BOTH));

// array_reduce empty with initial
$r = array_reduce([], fn($carry, $item) => $carry + $item, 100);
var_dump($r); // 100

// array_reduce empty no initial
$r = array_reduce([], fn($carry, $item) => $carry + $item);
var_dump($r); // null

// array_reduce normal
$r = array_reduce([1, 2, 3, 4, 5], fn($c, $v) => $c + $v, 0);
echo $r, "\n";
$r = array_reduce([1, 2, 3], fn($c, $v) => $c . "/" . $v, "start");
echo $r, "\n";

// array_column basic
$rows = [
    ["id" => 1, "name" => "alice", "age" => 30],
    ["id" => 2, "name" => "bob", "age" => 25],
    ["id" => 3, "name" => "carol", "age" => 40],
];
print_r(array_column($rows, "name"));
print_r(array_column($rows, "age", "name"));
print_r(array_column($rows, "name", "id"));
print_r(array_column($rows, null, "id"));

// array_column with missing key returns empty for that row
$rows2 = [
    ["a" => 1, "b" => 2],
    ["a" => 3], // no b
    ["a" => 5, "b" => 6],
];
print_r(array_column($rows2, "b"));

// array_column with non-scalar index_key
$rows3 = [
    ["k" => "x", "v" => 1],
    ["k" => "y", "v" => 2],
];
print_r(array_column($rows3, "v", "k"));

// array_column with int keys
$rows4 = [
    [10 => "a", 20 => "b"],
    [10 => "c", 20 => "d"],
];
print_r(array_column($rows4, 10));
print_r(array_column($rows4, 20, 10));

// array_column on objects
class Row {
    public int $id;
    public string $name;
    public function __construct(int $i, string $n) { $this->id = $i; $this->name = $n; }
}
$objs = [new Row(1, "alice"), new Row(2, "bob"), new Row(3, "carol")];
print_r(array_column($objs, "name"));
print_r(array_column($objs, "name", "id"));
print_r(array_column($objs, null, "id"));

// array_column on stdClass
$arr = [
    (object)["k" => "a", "v" => 1],
    (object)["k" => "b", "v" => 2],
];
print_r(array_column($arr, "v"));
print_r(array_column($arr, "v", "k"));

// array_combine into array_column workflow
$ks = ["a", "b", "c"];
$vs = [1, 2, 3];
print_r(array_combine($ks, $vs));

// array_walk on assoc
$arr = ["a" => 1, "b" => 2];
array_walk($arr, function (&$v, $k) { $v = $k . "-" . $v; });
print_r($arr);

// array_walk preserves keys/order
$arr = [5 => "a", 10 => "b", "x" => "c"];
$visit = [];
array_walk($arr, function ($v, $k) use (&$visit) {
    $visit[] = "$k=$v";
});
print_r($visit);
print_r($arr);
