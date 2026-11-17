<?php
// the named arguments a variadic collects keep their names in backtraces
function test($a, ...$rest) {
    $bt = debug_backtrace();
    var_dump($bt[0]['args']);
    ob_start();
    debug_print_backtrace();
    echo preg_replace('/^#0 .*?: /m', '#0 ', ob_get_clean());
}
function secret($a, #[\SensitiveParameter] ...$x) {
    ob_start();
    debug_print_backtrace();
    echo preg_replace('/^#0 .*?: /m', '#0 ', ob_get_clean());
}
test(1, 2, x: 3, y: [4]);
secret(b: 1, a: 2, c: 3);
