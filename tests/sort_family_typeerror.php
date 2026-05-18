<?php
// regression: full sort + array_product family throws PHP-format TypeError
// ('Argument #1 ($array) must be of type array, <type> given') on non-array
// input instead of silently returning false/0/1
$bad = "str";
foreach (['sort', 'rsort', 'asort', 'arsort', 'ksort', 'krsort',
          'natsort', 'natcasesort', 'array_product'] as $fn) {
    try { $fn($bad); echo "$fn: no-throw\n"; }
    catch (\TypeError $e) { echo "$fn: " . $e->getMessage() . "\n"; }
}

// usort family (2 args, callback required)
$cmp = fn($a, $b) => $a <=> $b;
foreach (['usort', 'uasort', 'uksort'] as $fn) {
    try { $fn($bad, $cmp); echo "$fn: no-throw\n"; }
    catch (\TypeError $e) { echo "$fn: " . $e->getMessage() . "\n"; }
}

// verify normal case still works
$a = [3, 1, 2];
sort($a);
print_r($a);
asort($a);
print_r($a);
