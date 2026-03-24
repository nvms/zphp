<?php

// regression: continue in foreach skipped iter_advance, causing infinite loop

$items = [1, 2, 3, 4, 5];
$result = [];
foreach ($items as $item) {
    if ($item % 2 === 0) continue;
    $result[] = $item;
}
echo implode(",", $result) . "\n";

// continue with all items skipped
$skipped = 0;
foreach ([1, 2, 3] as $x) {
    $skipped++;
    if ($x > 0) continue;
    echo "should not print\n";
}
echo "skipped:" . $skipped . "\n";

// continue with key => value
$out = [];
foreach (["a" => 1, "b" => 2, "c" => 3] as $k => $v) {
    if ($k === "b") continue;
    $out[] = $k . "=" . $v;
}
echo implode(",", $out) . "\n";

// nested foreach with continue
$rows = [[1, 2], [3, 4]];
$flat = [];
foreach ($rows as $row) {
    foreach ($row as $val) {
        if ($val === 2) continue;
        $flat[] = $val;
    }
}
echo implode(",", $flat) . "\n";
