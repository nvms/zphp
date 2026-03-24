<?php

// empty array
$count = 0;
foreach ([] as $v) {
    $count++;
}
echo "empty: $count\n";

// nested foreach same var name
$result = "";
foreach ([1, 2] as $v) {
    foreach ([10, 20] as $v) {
        $result .= $v . " ";
    }
}
echo trim($result) . "\n";

// foreach preserves keys on associative
$assoc = ["b" => 2, "a" => 1, "c" => 3];
$keys = [];
foreach ($assoc as $k => $v) {
    $keys[] = $k;
}
echo implode(",", $keys) . "\n";

// foreach with nested arrays
$matrix = [[1, 2], [3, 4], [5, 6]];
$sums = [];
foreach ($matrix as $row) {
    $s = 0;
    foreach ($row as $cell) {
        $s += $cell;
    }
    $sums[] = $s;
}
echo implode(",", $sums) . "\n";

// foreach modifying external variable
$total = 0;
foreach ([10, 20, 30, 40] as $n) {
    $total += $n;
}
echo $total . "\n";
