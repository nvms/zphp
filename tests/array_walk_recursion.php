<?php
// natives that walk nested arrays protect each array while they are inside
// it, as php does, so an array that contains itself is caught

$a = [1, 2, 'three'];
$a[] = &$a;
var_dump(count($a));
var_dump(count($a, COUNT_RECURSIVE));
$nested = [1, [2, [3, 4]], [5]];
var_dump(count($nested, COUNT_RECURSIVE));
// the same array twice, side by side, is not recursion
$inner = [1, 2];
var_dump(count([$inner, $inner], COUNT_RECURSIVE));

$one = 1;
$two = 2;
$names = ["one", &$names];
try {
    var_dump(compact($names));
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
$deep = ["one", [["two"]]];
$deep[1][0][] = &$deep;
try {
    var_dump(compact($deep));
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
$list = ["one", "two"];
var_dump(compact($list, [$list]));

$x = ["k1" => ["k2" => []]];
$x["k1"]["k2"]["k3"] = &$x;
$y = ["k1" => ["k2" => []]];
$y["k1"]["k2"]["k3"] = &$y;
try {
    array_merge_recursive($x, $y);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump(array_merge_recursive(["a" => [1, "b" => [2]]], ["a" => [3, "b" => [4]]]));
$x["k1"]["k2"]["k3"] = null;
$y["k1"]["k2"]["k3"] = null;
