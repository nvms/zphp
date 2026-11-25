<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\fuzz_001 {
    echo "# fuzz_001\n";
    $closure = function($a, $b) {};

    echo (string) new ReflectionFunction($closure(1, ?));
}

namespace pfa\fuzz_003 {
    echo "# fuzz_003\n";
    class Foo {
        function __call($name, $args) {
            var_dump($args);
        }
    }
    $foo = new Foo;
    $bar = $foo->method(1, ...);
    $bar(2);
}

namespace pfa\fuzz_004 {
    echo "# fuzz_004\n";
    function foo($a, $b) {
        return $a + $b;
    }

    $foo = foo(b: 10, ...);

    try {
        $foo->__invoke(UNDEFINED);
    } catch (\Throwable $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\fuzz_005 {
    echo "# fuzz_005\n";
    function foo(int $day = 1, int $month = 1, int $yearh = 1, int $year = 2005) {
    }

    $foo = foo(month: 12, ...);

    $bar = $foo(year: 2016, ...);

    ?>
    ==DONE==
}

namespace pfa\fuzz_006 {
    echo "# fuzz_006\n";
    function foo(int $day = 1, int $month = 1, int $year = 2005) {
        var_dump($day);
    }

    $foo = foo(month: 12, ...);

    $foo(year: 2025);
}

namespace pfa\fuzz_007 {
    echo "# fuzz_007\n";
    function foo(int $day = 1, int $month = UNDEFINED, int $year = 2005) {
    }

    $foo = foo(year: 2006, ...);

    try {
        $foo(2);
    } catch (\Throwable $e) {
        echo $e->getMessage(), "\n";
    }
}
