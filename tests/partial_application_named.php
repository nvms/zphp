<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\named_placeholders {
    echo "# named_placeholders\n";
    class A {}
    class B {}
    class C {}

    function foo($a = 1, $b = 2, $c = 3) {
        var_dump($a, $b, $c);
    }

    echo "# Case 1\n";

    $c = foo(b: ?);

    echo (string) new ReflectionFunction($c);

    $c(new B);

    echo "# Case 2\n";

    $c = $c(?);

    echo (string) new ReflectionFunction($c);

    $c(new B);

    echo "# Case 3\n";

    $c = foo(?, ?);
    try {
        $c = $c(b: ?);
    } catch (\Throwable $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    echo "# Case 4\n";

    function bar($a = 1, $b = 2, ...$c) {
        var_dump($a, $b, $c);
    }

    $d = bar(b: ?, ...);

    echo (string) new ReflectionFunction($d);

    $d(new B, new A, new C);

    echo "# Case 5\n";

    try {
        $d = bar(?, a: ?);
    } catch (\Throwable $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    echo "# Case 6\n";

    try {
        $d = bar(c: ?, ...);
    } catch (\Throwable $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}
