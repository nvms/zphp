<?php
// once memory_limit is crossed, php's backtraces stop after the first
// frame: the fatal error lists the function that was running and {main}
ini_set('memory_limit', '4M');
ini_set('log_errors', '0');
ini_set('display_errors', '1');

function fill($y) {
    $a = [];
    for ($i = 0; $i < 100000; $i++) $a[] = str_repeat('x', 100) . $i;
    return count($a);
}
function outer($x) {
    return fill($x + 1) + 1;
}
outer(2);
