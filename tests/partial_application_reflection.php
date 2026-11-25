<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\reflection_001 {
    echo "# reflection_001\n";
    function foo($a = 1, $b = 5, $c = 10) {

    }

    $foo = foo(?, ...);

    echo (string) new ReflectionFunction($foo);

    $foo = foo(?, ?, ...);

    echo (string) new ReflectionFunction($foo);

    $foo = foo(?, ?, ?);

    echo (string) new ReflectionFunction($foo);
}

namespace pfa\reflection_002 {
    echo "# reflection_002\n";
    function foo($a, ...$b) {
        var_dump(func_get_args());
    }

    $foo = foo(?);

    echo (string) new ReflectionFunction($foo);

    $foo = foo(?, ...);

    echo (string) new ReflectionFunction($foo);

    $foo = foo(?, ?);

    echo (string) new ReflectionFunction($foo);

    $foo = foo(?, ?, ?);

    echo (string) new ReflectionFunction($foo);
}

namespace pfa\reflection_003 {
    echo "# reflection_003\n";
    $foo = sprintf(?);

    echo (string) new ReflectionFunction($foo);

    $foo = sprintf(?, ...);

    echo (string) new ReflectionFunction($foo);

    $foo = sprintf(?, ?);

    echo (string) new ReflectionFunction($foo);
}

namespace pfa\reflection_004 {
    echo "# reflection_004\n";
    var_dump((new ReflectionFunction('sprintf'))->isAnonymous());

    var_dump((new ReflectionFunction(function () {}))->isAnonymous());

    var_dump((new ReflectionFunction(sprintf(?)))->isAnonymous());
}

namespace pfa\reflection_005 {
    echo "# reflection_005\n";
    var_dump((new ReflectionFunction('sprintf'))->isClosure());

    var_dump((new ReflectionFunction(function () {}))->isClosure());

    var_dump((new ReflectionFunction(sprintf(?)))->isClosure());
}

namespace pfa\return_type {
    echo "# return_type\n";
    function foo($a) : array {}

    echo (string) new ReflectionFunction(foo(new stdClass, ...));
}

namespace pfa\attributes_001 {
    echo "# attributes_001\n";
    #[Attribute]
    class Test {}

    #[NoDiscard] #[Test]
    function f($a, #[SensitiveParameter] $b, #[Test] ...$c) {
    }

    function dump_attributes($function) {
        $r = new ReflectionFunction($function);
        var_dump($r->getAttributes());

        foreach ($r->getParameters() as $i => $p) {
            echo "Parameter $i:\n";
            var_dump($p->getAttributes());
        }
    }

    echo "# Orig attributes:\n";

    dump_attributes('f');

    $f = f(1, ?, ?, ...);

    echo "# PFA attributes:\n";

    dump_attributes($f);
}

namespace pfa\attributes_003 {
    echo "# attributes_003\n";
    #[NoDiscard] function f($a) {
    }

    $f = f(?);
    $f(1);

    (void) $f(1);
}

namespace pfa\static_vars_001 {
    echo "# static_vars_001\n";
    function foo($a) {
        static $var = 0;

        ++$var;

        return $var;
    }

    var_dump(foo(new stdClass));

    $foo = foo(new stdClass, ...);

    var_dump($foo());
}

namespace pfa\static_vars_002 {
    echo "# static_vars_002\n";
    $closure = function ($a) {
        static $var = 0;

        ++$var;

        return $var;
    };

    var_dump($closure(new stdClass));

    $foo = $closure(new stdClass, ...);
    $closure = null;

    var_dump($foo());
}

namespace pfa\static_vars_003 {
    echo "# static_vars_003\n";
    $closure = function ($a) {
        static $var = 0;

        ++$var;

        return $var;
    };

    var_dump($closure(new stdClass));

    $foo = $closure(?);
    $closure = null;

    $bar = $foo(?);
    $foo = null;

    var_dump($bar(new stdClass));
}
