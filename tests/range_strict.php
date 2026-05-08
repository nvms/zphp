<?php
// step=0 throws ValueError
try {
    range(1, 5, 0);
} catch (\ValueError $e) {
    echo "step0: ", $e->getMessage(), "\n";
}

// step bigger than span throws
try {
    range(1, 5, 10);
} catch (\ValueError $e) {
    echo "big: ", $e->getMessage(), "\n";
}

// float step bigger than span
try {
    range(0.0, 1.0, 5.0);
} catch (\ValueError $e) {
    echo "fbig: ", $e->getMessage(), "\n";
}

// range() with floats
$r = range(0, 1, 0.1);
echo count($r), "\n";
foreach ($r as $v) echo $v, "\n";

print_r(range(0, 1, 0.25));
print_r(range(1.5, 3.5, 0.5));
print_r(range(10, 0, 2));
print_r(range(1, 10, 2.5));
print_r(range(3, 3));

// print_r of float uses 14-digit precision (not shortest-roundtrip)
print_r([0.1 + 0.1 + 0.1]);
print_r(['v' => 1.0 / 3.0]);

// in_array / array_search strict mode
var_dump(in_array(0, ['a', 'b']));   // false PHP 8
var_dump(in_array('1', [1, 2]));     // true loose
var_dump(in_array('1', [1, 2], true));// false strict
var_dump(array_search('1', [1, 2, 3]));     // 0 loose
var_dump(array_search('1', [1, 2, 3], true)); // false strict
