<?php
// array_rand($arr, 1) returns a scalar key just like array_rand($arr).
// only num > 1 returns an array of keys. no assertion depends on which key the
// random pick returned, only on its type and membership

$assoc = ["a" => 1, "b" => 2, "c" => 3];
var_dump(is_array(array_rand($assoc)));
var_dump(is_array(array_rand($assoc, 1)));
var_dump(is_array(array_rand($assoc, 2)));

// string keys
$k = array_rand($assoc);
echo gettype($k) . " " . (array_key_exists($k, $assoc) ? "in" : "missing") . "\n";
$k = array_rand($assoc, 1);
echo gettype($k) . " " . (array_key_exists($k, $assoc) ? "in" : "missing") . "\n";

// numeric keys
$list = [10, 20, 30, 40];
$k = array_rand($list);
echo gettype($k) . " " . (array_key_exists($k, $list) ? "in" : "missing") . "\n";
$k = array_rand($list, 1);
echo gettype($k) . " " . (array_key_exists($k, $list) ? "in" : "missing") . "\n";

// num > 1 keeps the array-of-keys form distinct keys of the source array
$picks = array_rand($assoc, 2);
echo gettype($picks) . " " . count($picks) . "\n";
echo count(array_unique($picks)) === 2 ? "distinct\n" : "dupes\n";
foreach ($picks as $p) {
    echo (array_key_exists($p, $assoc) ? "in " : "missing ");
}
echo "\n";

// asking for every key is deterministic, all keys in their original order
var_dump(array_rand($list, 4) === [0, 1, 2, 3]);
var_dump(array_rand($assoc, 3) === ["a", "b", "c"]);

// single-element array
$one = ["only" => 1];
var_dump(array_rand($one));
var_dump(array_rand($one, 1));

// out of range num still raises the ValueError
try {
    array_rand($assoc, 4);
} catch (ValueError $e) {
    echo get_class($e) . ": " . $e->getMessage() . "\n";
}
try {
    array_rand($assoc, 0);
} catch (ValueError $e) {
    echo get_class($e) . ": " . $e->getMessage() . "\n";
}
