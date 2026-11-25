<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\constexpr_001 {
    echo "# constexpr_001\n";
    function f($a = g("foo", ?)) {
        return $a(1);
    }

    function g(string $a, int $b) {
        return [$a, $b];
    }

    class C {
        static function f($a = self::g("foo", ?)) {
            return $a(1);
        }

        static function g(string $a, int $b) {
            return [$a, $b];
        }
    }

    var_dump(f());
    var_dump(f());
    var_dump(C::f());
    var_dump(C::f());
}

namespace pfa\constexpr_003 {
    echo "# constexpr_003\n";
    function f($a = g(c: ?, ...)) {
        return $a(1.5, b: 3);
    }

    function g(string $a = 'hello', int $b = 2, float $c = 0) {
        return [$a, $b, $c];
    }

    var_dump(f());
}

namespace pfa\constexpr_004 {
    echo "# constexpr_004\n";
    function f($a = g(?, foo: 'bar', ...)) {
        return $a(1, bar: 'baz');
    }

    function g(...$args) {
        return [$args];
    }

    var_dump(f());
}

namespace pfa\constexpr_010 {
    echo "# constexpr_010\n";
    function f($a = g(?)) {
    }

    function g($a, $b) {
    }

    try {
        f();
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\constexpr_011 {
    echo "# constexpr_011\n";
    function f($a = g(strlen(?), e: strlen(?), a: strlen(?), ...)) {
    }

    function g($a, $b, $c, $d, $e) {
    }

    function h($a = i(strlen(?), a: strlen(?), b: invalid(?), ...)) {
    }

    function i(...$args) {
    }

    function j($a = g(c: new stdClass, ...), $b = g(c: MISSING_CONST + 1, ...)) {
    }

    try {
        f();
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    try {
        h();
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }

    try {
        j();
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\constexpr_012 {
    echo "# constexpr_012\n";
    function f($a = g(new stdClass, g(...), ...)) {
        return $a(1);
    }

    function g($a, $b, $c) {
        return [$a, $b, $c];
    }

    var_dump(f());
}

namespace pfa\constexpr_014 {
    echo "# constexpr_014\n";
    #[Attribute]
    class A {
        function __construct(public mixed $fn) {}
    }

    #[A(strlen(?))]
    class C {
        const CC = strlen(?);

        #[A(strlen(?))]
        function f($arg = strlen(?)) {
            return $arg;
        }
    }

    const CC = strlen(?);

    echo "# Class const\n";
    var_dump((C::CC)('hello'));
    echo "# Const\n";
    var_dump((CC)('hello'));
    echo "# Class attr\n";
    var_dump((new ReflectionClass(C::class)->getAttributes(A::class)[0]->newInstance()->fn)('hello'));
    echo "# Method attr\n";
    var_dump((new ReflectionMethod(C::class, 'f')->getAttributes(A::class)[0]->newInstance()->fn)('hello'));
    echo "# Method default value\n";
    var_dump((new C()->f())('hello'));
}

namespace pfa\constexpr_016 {
    echo "# constexpr_016\n";
    function byRef($a, &$b) {}
    function byRefVariadic(&...$args) {}

    class C {
        public static function staticByRef($a, &$b) {}
    }

    function f1($x = byRef(new stdClass, new stdClass, ...)) {}
    function f2($x = byRef(b: new stdClass, a: ?)) {}
    function f3($x = byRefVariadic(new stdClass, ...)) {}
    function f4($x = byRefVariadic(extra: new stdClass, ...)) {}
    function f5($x = C::staticByRef(new stdClass, new stdClass, ...)) {}

    foreach (['f1', 'f2', 'f3', 'f4', 'f5'] as $f) {
        try {
            $f();
        } catch (Error $e) {
            echo get_class($e), ": ", $e->getMessage(), "\n";
        }
    }

    function f6($x = byRef(new stdClass, ?)) {
        return $x;
    }

    $partial = f6();
    $var = 1;
    var_dump($partial instanceof Closure);
    $partial($var);
}

namespace pfa\gh25007 {
    echo "# gh25007\n";
    function f($a, $b = 2, $c = 3) {
        var_dump(func_get_args());
    }

    const C1 = f(a: 1, b: ?);
    const C2 = f(a: 1, c: ?, b: ?);

    (C1)(4);
    (C2)(5, 6);
}

namespace pfa\oss_fuzz_540904105 {
    echo "# oss_fuzz_540904105\n";
    function foo($test, $extra) {}

    const C = foo(__METHOD__, ?);

    var_dump(C);
}

namespace pfa\rfc_examples_const_expr {
    echo "# rfc_examples_const_expr\n";
    class Foo
    {
        public function __construct(
            private \Closure $callback = bar(1, 2, ?),
        ) {}
    }

    class Example
    {
        public const BASE = 10;

        private Closure $arrayToInt = array_map(intval(?, self::BASE), ?);
    }

    ?>
    ==DONE==
}
