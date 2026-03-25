<?php
// array operations - tests array creation, access, manipulation
$n = 50000;

// build array
$arr = [];
for ($i = 0; $i < $n; $i++) {
    $arr[] = $n - $i;
}

// sum
$sum = 0;
for ($i = 0; $i < $n; $i++) {
    $sum += $arr[$i];
}

// filter to new array
$filtered = [];
for ($i = 0; $i < $n; $i++) {
    if ($arr[$i] % 3 === 0) {
        $filtered[] = $arr[$i];
    }
}

// map
$mapped = [];
for ($i = 0; $i < count($filtered); $i++) {
    $mapped[] = $filtered[$i] * 2;
}

echo "$sum\n";
echo count($filtered) . "\n";
echo count($mapped) . "\n";
