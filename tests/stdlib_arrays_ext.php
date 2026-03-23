<?php

// array_reduce
function sum_reducer($carry, $item) {
    return $carry + $item;
}
echo array_reduce([1, 2, 3, 4, 5], "sum_reducer", 0) . "\n";

function concat_reducer($carry, $item) {
    return $carry . $item;
}
echo array_reduce(["a", "b", "c"], "concat_reducer", "") . "\n";

// array_key_first / array_key_last
$a = ["x" => 1, "y" => 2, "z" => 3];
echo array_key_first($a) . "\n";
echo array_key_last($a) . "\n";

$b = [10, 20, 30];
echo array_key_first($b) . "\n";
echo array_key_last($b) . "\n";

// empty array
echo var_export(array_key_first([]), true) . "\n";

// array_replace
$base = ["a" => 1, "b" => 2, "c" => 3];
$replacement = ["b" => 20, "d" => 4];
$result = array_replace($base, $replacement);
echo $result["a"] . "\n";
echo $result["b"] . "\n";
echo $result["c"] . "\n";
echo $result["d"] . "\n";
