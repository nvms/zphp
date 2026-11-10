<?php
// internal functions refuse a non-array for an `array` parameter, naming the
// parameter unless it is variadic
function t(callable $f) {
    try {
        var_dump($f());
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
class C {}
t(fn() => array_merge([1], 2));
t(fn() => array_merge([1], [2], "x"));
t(fn() => array_search(1, new C));
t(fn() => in_array(1, null));
t(fn() => array_keys("abc"));
t(fn() => array_unique(new ArrayObject([1])));
t(fn() => array_fill_keys(5, 1));
t(fn() => array_combine([1], 2.5));
$x = "not an array";
t(function () use ($x) { return sort($x); });
t(fn() => count([1, 2]));
