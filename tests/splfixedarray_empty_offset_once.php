<?php
// empty() on an SplFixedArray converts its offset once and reads the
// element itself, unless a subclass overrides offsetExists()
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) { echo "$no: $msg\n"; return true; });
$a = new SplFixedArray(4);
$a[0] = 0;
$a[1] = 'x';
$a[2] = [];
$r = fopen('php://memory', 'r');
foreach ([0, 1, 1.5, 2.5, true, '1', ' 1', 9] as $k) {
    try {
        var_dump(empty($a[$k]));
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
var_dump(empty($a[$r]));
foreach ([[], new stdClass] as $k) {
    try {
        var_dump(empty($a[$k]));
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
class Sub extends SplFixedArray {
    function offsetGet($i): mixed { echo "offsetGet\n"; return parent::offsetGet($i); }
}
$s = new Sub(2);
$s[1] = 5;
var_dump(empty($s[1]), empty($s[0]));
class Exists extends SplFixedArray {
    function offsetExists($i): bool { echo "offsetExists\n"; return true; }
}
$e = new Exists(2);
var_dump(empty($e[0]));
