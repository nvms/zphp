<?php
print_r(array_combine([], []));

try { array_combine([1, 2], [1]); echo "no\n"; }
catch (\ValueError $e) { echo "ve-mismatch\n"; }

print_r(array_combine(["a"], [42]));

print_r(array_combine([1, 2, 3], ["a", "b", "c"]));

$arr = ["a" => 1, "b" => 2, "c" => 3];
array_walk($arr, function (&$v, $k) {
    $v = $k . "=" . $v;
});
print_r($arr);

$arr = ["x" => 10, "y" => 20];
array_walk($arr, function ($v, $k) use (&$result) {
    $result[$k] = $v * 2;
});
print_r($result ?? []);

$arr = [10, 20, 30];
array_walk($arr, function (&$v, $k) {
    $v = "[$k:$v]";
});
print_r($arr);

class O { public function __construct(public int $n) {} }
$arr = [new O(1), new O(2), new O(3)];
$even = array_filter($arr, fn(O $o) => $o->n % 2 === 0);
echo count($even), "\n";
foreach ($even as $o) echo $o->n, " ";
echo "\n";

$bigger = array_filter($arr, fn(O $o, $k) => $o->n > $k, ARRAY_FILTER_USE_BOTH);
echo count($bigger), "\n";

$mapped = array_map(fn(O $o) => $o->n * 10, $arr);
print_r($mapped);

class StrObj { public function __construct(public string $name) {} }
$rows = [
    "alice" => new StrObj("Alice Wong"),
    "bob" => new StrObj("Bob Smith"),
    "carol" => new StrObj("Carol Wang"),
];
$kept = array_filter($rows, function (StrObj $o, string $k) {
    return str_contains($o->name, "W");
}, ARRAY_FILTER_USE_BOTH);
foreach ($kept as $k => $o) echo "$k=$o->name\n";

$arr = [];
foreach ([new O(1), new O(2)] as $o) {
    $arr[] = $o;
}
$copy = $arr;
$copy[0]->n = 99;
echo $arr[0]->n, "/", $copy[0]->n, "\n";

$arr = [];
$collect = function ($v, $k) use (&$arr) {
    $arr[$k] = $v;
};
$tmp = ["a" => 1, "b" => 2]; array_walk($tmp, $collect);
print_r($arr);

$arr = [1.5, 2.5, 3.5, 4.5];
array_walk($arr, function (&$v) { $v = round($v); });
print_r($arr);

$obj_arr = [
    new O(1),
    new O(2),
    new O(3),
];
array_walk($obj_arr, function (O $o) { $o->n *= 100; });
foreach ($obj_arr as $o) echo $o->n, " ";
echo "\n";

$nested = [[1, 2], [3, 4], [5, 6]];
array_walk($nested, function (&$v) {
    $v = array_sum($v);
});
print_r($nested);

$boxes = [
    "first" => new O(1),
    "second" => new O(2),
];
$labels = array_map(fn($o, $k) => "$k:" . $o->n, $boxes, array_keys($boxes));
print_r($labels);

$names = ["one", "two", "three"];
$indexed = array_map(null, range(1, 3), $names);
print_r($indexed);

$counts = array_filter([0 => "a", 1 => "b", 2 => "c", 3 => ""], fn($v) => strlen($v) > 0);
print_r($counts);

$strings = ["foo", "bar", "baz"];
$lens = array_map("strlen", $strings);
print_r($lens);

$arr = [1, 2, 3];
$f = function (&$v, $k) {
    $v = "k=$k,v=$v";
};
array_walk($arr, $f);
print_r($arr);
