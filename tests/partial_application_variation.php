<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\variation_call_001 {
    echo "# variation_call_001\n";
    class Param {

        public function __toString() {
            return __CLASS__;
        }
    }

    class Foo {
        public function method($a, $b) {
            printf("%s: %s, %s\n", get_called_class(), $a, $b);
        }
    }

    class Bar extends Foo {

    }

    $bar = new Bar;
    $closure = $bar->method(?, new Param);

    $closure(1);

    $closure->call(/* newThis: */ new Foo(), 10);
}

namespace pfa\variation_closure_001 {
    echo "# variation_closure_001\n";
    $closure = function($a, $b) {
    };

    echo (string) new ReflectionFunction($closure(1, ?));

    $closure2 = function($a, $fn) {
    };

    echo (string) new ReflectionFunction($closure2(1, ?));
}

namespace pfa\variation_closure_002 {
    echo "# variation_closure_002\n";
    $closure = function($a, $b) {
        var_dump($a, $b);
    };

    $function = $closure->__invoke(1, ?);

    echo (string) new ReflectionFunction($function);

    $function(10);
}

namespace pfa\variation_closure_003 {
    echo "# variation_closure_003\n";
    class Foo {
        public function bar() {
            return function($a, $b) {
                return [$this, func_get_args()];
            };
        }
    }

    $foo = new Foo;

    $closure = $foo->bar();

    $function = $closure->__invoke(1, ?);

    echo (string) new ReflectionFunction($function);

    var_dump($function(10));
}

namespace pfa\variation_debug_001 {
    echo "# variation_debug_001\n";
    function bar($a = 1, $b = 2, ...$c) {

    }

    var_dump(bar(?, new stdClass, (int)getenv('A'), new stdClass, four: 4));
}

namespace pfa\variation_debug_002 {
    echo "# variation_debug_002\n";
    function notconst($value) {
        return getenv('A') ? $value : null;
    }

    var_dump(array_map(?, notconst([1, 2, 3]), notconst([4, 5, 6]), four: new stdClass, ...));
}

namespace pfa\variation_ex_001 {
    echo "# variation_ex_001\n";
    function test($a){}

    try {
        test(1, ...)(?);
    } catch (Error $ex) {
        echo $ex::class, ": ", $ex->getMessage(), "\n";
    }
}

namespace pfa\variation_gc_001 {
    echo "# variation_gc_001\n";
    #[AllowDynamicProperties]
    class Foo {

        public function __construct($a) {
            $this->method = self::__construct(new stdClass, ...);
        }
    }

    $foo = new Foo(new stdClass);
    $foo->bar = $foo;

    echo "OK";
}

namespace pfa\variation_gc_002 {
    echo "# variation_gc_002\n";
    $obj = new stdClass;
    $obj->prop = var_dump($obj, ?);

    echo "OK";
}

namespace pfa\variation_gc_003 {
    echo "# variation_gc_003\n";
    function test(...$args) {
    }

    $obj = new stdClass;
    $obj->prop = test(?, x: $obj);

    echo "OK";
}

namespace pfa\variation_invoke_001 {
    echo "# variation_invoke_001\n";
    function foo($a, $b) {
        return $a + $b;
    }

    $foo = foo(b: 10, ...);

    var_dump($foo->__invoke(32));

    try {
        $foo->nothing();
    } catch (Error $ex) {
        echo $ex::class, ": ", $ex->getMessage(), "\n";
    }
}

namespace pfa\variation_nocall_001 {
    echo "# variation_nocall_001\n";
    function test($a, $b) {}

    test(?, new stdClass);

    echo "OK";
}

namespace pfa\variation_nocall_002 {
    echo "# variation_nocall_002\n";
    class Foo {
        function method($a) {}
    }
    class Dtor {
        public function __construct(public int $id) {}
        public function __destruct() {
            echo __METHOD__, " ", $this->id, "\n";
        }
    }
    $foo = new Foo;
    $f = $foo->method(?);
    $g = $f(?);

    $map = new WeakMap();
    $map[$f] = new Dtor(1);
    $map[$g] = new Dtor(2);

    unset($f);
    unset($g);

    echo "OK";
}

namespace pfa\variation_parent_001 {
    echo "# variation_parent_001\n";
    class Foo {
        public function method($a, $b, ...$c) {
            return function() {
                return $this;
            };
        }
    }

    $foo = new Foo();
    $bar = $foo->method(10, ...);
    $baz = $bar(20, ...);

    var_dump($baz, $c = $baz(), $c() === $foo);
}

namespace pfa\variation_scope_001 {
    echo "# variation_scope_001\n";
    class Foo {
        public function method($a) {
            printf("%s::%s\n", get_called_class(), __FUNCTION__);
        }
    }

    $foo = new Foo;

    $bar = $foo->method(new stdClass, ...);

    $bar();
}

namespace pfa\variation_variadics_001 {
    echo "# variation_variadics_001\n";
    function foo($a, ...$b) {
        var_dump($a, ...$b);
    }

    $foo = foo(10, 100, ...);

    echo (string) new ReflectionFunction($foo);

    $foo(1000, 10000);
}

namespace pfa\variation_variadics_002 {
    echo "# variation_variadics_002\n";
    $sprintf = sprintf("%d %d %d", 100, ...);

    echo (string) new ReflectionFunction($sprintf);

    echo $sprintf(1000, 10000);
}

namespace pfa\variation_variadics_004 {
    echo "# variation_variadics_004\n";
    function foo(int $day = 1, int $month = 1, int $year = 2005) {
        printf("%04d-%02d-%02d\n", $year, $month, $day);
    }

    $foo = foo(year: 2006, ...);

    echo "# Bound year, pass day:\n";

    $foo(2);

    $foo = foo(month: 12, ...);

    $bar = $foo(year: 2016, ...);

    echo "# Bound month, pass day:\n";

    $foo(2);

    echo "# Bound month, bound year, pass day:\n";

    $bar(2);

    echo "# Bound month, no args:\n";

    $foo();

    echo "# Bound month, bound year, no args:\n";

    $bar();
}

namespace pfa\variation_variadics_006 {
    echo "# variation_variadics_006\n";
    function foo($a) {
        var_dump(func_get_args());
    }

    $foo = foo(a: "a", ...);

    $foo();
}

namespace pfa\variation_variadics_007 {
    echo "# variation_variadics_007\n";
    function appliesCb($cb) { return runsCb($cb(1, ?, ...)); }

    function runsCb($cb) {
            return $cb(2, 3);
    }

    var_dump(appliesCb(fn($a, $b) => $a + $b));
}

namespace pfa\variation_variadics_008 {
    echo "# variation_variadics_008\n";
    function foo(...$c) {}

    $fn = foo(?);

    try {
        $fn(?, ?);
    } catch (Error $ex) {
        echo $ex->getMessage() . PHP_EOL;
    }
}
