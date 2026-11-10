<?php
// min and max: php's int and float fast paths, zend_compare otherwise
function t(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
t(fn() => max(1));
t(fn() => min(new stdClass));
t(fn() => max([]));
t(fn() => max(1, 2.5, "3"));
t(fn() => min(PHP_INT_MAX, PHP_INT_MAX - 1, 1.8446744073709552E+19));
t(fn() => max(PHP_INT_MIN, PHP_INT_MIN + 1, -1.8446744073709552E+19));
t(fn() => max(1, 1.0));
t(fn() => min(1.0, 1));
t(fn() => max("apple", "banana", 10));
t(fn() => min([0, -0.0]));
t(fn() => max([1, "1", 1.0]));
t(fn() => min(["b" => 2, "a" => 1, "c" => 3]));
t(fn() => max([[1, 2], [1, 3]]));
t(fn() => max("abc", [1]));
t(fn() => min(null, false, 0));
