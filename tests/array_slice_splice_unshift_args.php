<?php
// argument parsing for array_slice and array_splice, a null splice length,
// and array_unshift with nothing to add
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
function t(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
$a = [1, 2, 3, 4];
t(fn() => array_slice($a, 1, "2"));
t(fn() => array_slice($a, 1, "x"));
t(fn() => array_slice($a, "1.5"));
t(fn() => array_slice($a, 1, null, "yes"));
t(fn() => array_slice($a, 10, []));
$b = ["red", "green", "blue", "yellow"];
var_dump(array_splice($b, 2, null), $b);
$c = [1, 2, 3];
t(fn() => array_splice($c, "a"));
$d = [1, 2, 3];
var_dump(array_unshift($d), array_unshift($d, ...[]), $d);
