<?php
// an internal function's string parameters (and int|float ones) are
// converted in place by its argument parsing, so its trace frame shows the
// converted values; int, float and bool parameters keep the argument
ini_set("zend.exception_string_param_max_len", "15");
function show(callable $f) {
    try {
        $f();
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n", str_replace(__FILE__, "FILE", $e->getTraceAsString()), "\n";
    }
}
class TestClass {}
show(fn() => str_repeat(true, -1));
show(fn() => str_repeat(5, "-1"));
show(fn() => str_repeat(1.5, -2));
show(fn() => array_fill(0, "-1", 1.5));
show(fn() => range(1, 2, "0"));
show(fn() => range(1, 2, false));
show(fn() => new ReflectionMethod(true));
show(fn() => new ReflectionMethod(3));
show(fn() => new ReflectionMethod(true, 'foo'));
show(fn() => new ReflectionMethod('TestClass', true));
show(fn() => new ReflectionClass(12));
show(fn() => str_pad("x", 5, 7, 99));
