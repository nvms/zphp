<?php
function sum(int ...$nums): int {
    $total = 0;
    foreach ($nums as $n) {
        $total += $n;
    }
    return $total;
}
echo sum(1, 2, 3) . "\n";
echo sum(10, 20) . "\n";
echo sum() . "\n";

function first($a, ...$rest) {
    return $a . " +" . count($rest);
}
echo first("hello", "a", "b", "c") . "\n";

// spread in call (not yet supported, tested in array_spread.php for array context)
