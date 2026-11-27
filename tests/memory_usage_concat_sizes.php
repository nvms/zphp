<?php
// a concatenation's result counts as php's zend_string for it: a 24-byte
// header, the bytes and a terminator, in php's allocator bins and pages
function measure(int $n) {
    $left = str_repeat('a', intdiv($n, 2));
    $right = str_repeat('b', $n - intdiv($n, 2));
    $before = memory_get_usage();
    $joined = $left . $right;
    $after = memory_get_usage();
    return $after - $before;
}

foreach ([2, 7, 8, 39, 40, 100, 1000, 3047, 3048, 4071, 4072, 100000, 2093031, 2097152] as $n) {
    echo $n, ": ", measure($n), "\n";
}
