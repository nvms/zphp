<?php
// array_sum and array_product add and multiply like php's operators, warn
// for what they cannot use, and overflow into floats
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
class Obj {}
$fp = fopen("php://memory", "r");
var_dump(array_sum([1, 2.5, "3", "4.5", null, true, false]));
var_dump(array_product([2, "3", 1.5]));
var_dump(array_sum(["abc", "1x", " 2 ", [1], new Obj]));
var_dump(array_product(["abc", 5]));
var_dump(array_sum([$fp, 1]) > 1);
var_dump(array_product([PHP_INT_MAX, 2]));
var_dump(array_sum([PHP_INT_MAX, 1]));
var_dump(array_product(array_fill(0, 70, 2)));
var_dump(array_sum([]), array_product([]));
$x = 5;
$refs = [&$x, 2];
var_dump(array_sum($refs), array_product($refs));

// array_flip skips what cannot be a key, array_rand refuses an empty array
var_dump(array_flip([1, "a", 1.5, null, true, [1]]));
try {
    array_rand([]);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    array_pad([], PHP_INT_MAX, 0);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(array_change_key_case(["Ab" => 1, 2 => 3], -5));
var_dump(array_change_key_case(["Ab" => 1], CASE_LOWER));
try {
    array_change_key_case(["Ab" => 1], "upper");
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
