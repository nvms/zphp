<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\references_001 {
    echo "# references_001\n";
    function foo($a, $b) {
        $b = 2;
    }

    $a = ['unchanged because foo() doesn\'t take by reference'];
    $b = &$a[0];

    $foo = foo(1, ?);
    $foo($b);

    var_dump($a, $b);
}

namespace pfa\references_002 {
    echo "# references_002\n";
    function foo($a, &$b) {
        $b = 2;
    }

    $a = ['this will be changed'];
    $b = &$a[0];

    $foo = foo(1, ?);
    $foo($b);

    var_dump($a, $b);
}

namespace pfa\references_003 {
    echo "# references_003\n";
    function foo($a, &$b) {
        $a = 2;
    }

    $foo = foo(1, ?);

    try {
        $foo(2);
    } catch (\Throwable $e) {
        echo $e->getMessage(), "\n";
    }
}

namespace pfa\references_004 {
    echo "# references_004\n";
    function foo($a, &...$args) {
        foreach ($args as &$arg) {
            $arg = -$arg;
        }
    }

    $b = 2;
    $c = 3;
    $d = 4;

    $foo = foo(1, $b, ?, ...);

    echo (string) new ReflectionFunction($foo), "\n";

    $foo($c, $d);

    var_dump($b, $c, $d);
}

namespace pfa\references_005 {
    echo "# references_005\n";
    function &foo(&$a) {
        return $a;
    }

    $f = foo(?);
    $a = [];
    $b = &$f($a);
    $a[0] = 1;

    var_dump($a, $b);
}
