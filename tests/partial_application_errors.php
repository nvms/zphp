<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\errors_002 {
    echo "# errors_002\n";
    function foo($a) {
    }

    try {
        foo(?, a: 1);
    } catch (Error $ex) {
        printf("%s: %s\n", $ex::class, $ex->getMessage());
    }
}

namespace pfa\errors_003 {
    echo "# errors_003\n";
    function foo($a, ...$b) {

    }

    function bar($a, $b, $c) {}

    $foo = foo(?);

    try {
        $foo();
    } catch (Error $ex) {
        printf("%s: %s\n", $ex::class, $ex->getMessage());
    }

    $foo = foo(?, ?);

    try {
        $foo(1);
    } catch (Error $ex) {
        printf("%s: %s\n", $ex::class, $ex->getMessage());
    }

    $bar = bar(?, ?, ...);

    try {
        $bar(1);
    } catch (Error $ex) {
        printf("%s: %s\n", $ex::class, $ex->getMessage());
    }

    class Foo {
        public function bar($a, ...$b) {}
    }

    $foo = new Foo;

    $bar = $foo->bar(?);

    try {
        $bar();
    } catch (Error $ex) {
        printf("%s: %s\n", $ex::class, $ex->getMessage());
    }

    $repeat = str_repeat('a', ...);

    try {
        $repeat();
    } catch (Error $ex) {
        printf("%s: %s\n", $ex::class, $ex->getMessage());
    }

    $usleep = usleep(?);

    try {
        $usleep();
    } catch (Error $ex) {
        printf("%s: %s\n", $ex::class, $ex->getMessage());
    }

    $usleep(1, 2);
}

namespace pfa\errors_005 {
    echo "# errors_005\n";
    $f = function ($a, $b, $c = null) {};

    $g = $f->__invoke(0, 0, ?);
    echo "No error\n";

    try {
        $g = $f->__invoke(0, 0, ...);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\errors_006 {
    echo "# errors_006\n";
    $f = array_keys(?, 42);
    var_dump($f([41, 42, 43]));

    $f = array_keys(?, '42', true);
    var_dump($f([41, 42, 43]));

    $f = array_keys(?, '42', strict: ?);
    var_dump($f([41, 42, 43], false));
    var_dump($f([41, 42, 43], true));

    try {
        // fn (array $array) => array_keys($array, ???, true)
        $f = array_keys(?, strict: true);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    try {
        // fn (array $array, mixed $filter_value = ???) => array_keys($array, $filter_value, true)
        $f = array_keys(?, strict: true, ...);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\rfc_examples_errors {
    echo "# rfc_examples_errors\n";
    function stuff(int $i, string $s, float $f, Point $p, int $m = 0) {}

    class Point {}

    $point = new Point();

    try {
        stuff(?);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    try {
        stuff(?, ?, ?, ?, ?, ?);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    try {
        stuff(?, ?, 3.5, $point, i: 5);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\rfc_examples_incompatible_functions {
    echo "# rfc_examples_incompatible_functions\n";
    try {
        (function ($f) { $f(?); })("func_get_arg");
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\non_dynamic_call_funcs {
    echo "# non_dynamic_call_funcs\n";
    function _func_get_arg() {
        return func_get_arg(?);
    }

    function _compact() {
        return compact(?);
    }

    function _extract() {
        return extract(?);
    }

    function _func_get_args() {
        return func_get_args(?);
    }

    function _func_num_args() {
        return func_num_args(?);
    }

    function _get_defined_vars() {
        return get_defined_vars(?);
    }

    foreach (['_func_get_arg', '_compact', '_extract', '_func_get_args', '_func_num_args', '_get_defined_vars'] as $func) {
        try {
            $func();
            echo "$func\n";
        } catch (Error $e) {
            echo $e::class, ": ", $e->getMessage(), "\n";
        }
    }
}
