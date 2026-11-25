<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\rfc_examples_eval_order {
    echo "# rfc_examples_eval_order\n";
    function getArg() {
        print __FUNCTION__ . PHP_EOL;
        return 'hi';
    }

    function speak(string $who, string $msg) {
        printf("%s: %s\n", $who, $msg);
    }

    $arrow = static fn($who) => speak($who, getArg());
    print "Arnaud\n";
    $arrow('Larry');

    $partial = speak(?, getArg());
    print "Arnaud\n";
    $partial('Larry');
}

namespace pfa\superfluous_args_are_forwarded {
    echo "# superfluous_args_are_forwarded\n";
    function f($a) {
        var_dump(func_get_args());
    }

    $f = f(?, ...);
    $f(1, 2, 3);

    $h = f(?);
    $h(1, 2, 3);

    function g($a,  ...$args) {
        var_dump(func_get_args());
    }

    $g = g(?, ...);
    $g(1, 2, 3);
}

namespace pfa\extra_named {
    echo "# extra_named\n";
    function foo(...$args) {
        var_dump($args);
    }

    $foo = foo(foo: "foo", ...);

    $bar = $foo(bar: "bar", ...);

    $baz = $bar(baz: "baz", ...);

    $baz();

    $foo = foo(...);

    $bar = $foo(bar: "bar", ...);

    $baz = $bar(baz: "baz", ...);

    $baz();

    $foo = foo(foo: "foo", ...);

    $foo(bar: "bar");
}

namespace pfa\this {
    echo "# this\n";
    class Foo {
        public function method($a, $b) {
            return $this;
        }
    }

    $foo = new Foo;

    $bar = $foo->method(new stdClass, ...);

    $baz = $bar(new stdClass, ...);

    var_dump($foo === $baz());
}

namespace pfa\function_name {
    echo "# function_name\n";
    function g($a) {}

    class C {
        static function m() {
            echo "# From a method:\n";
            var_dump((new ReflectionFunction(g(?)))->getName());
        }
    }

    function f() {
        echo "# From a function:\n";
        var_dump((new ReflectionFunction(g(?)))->getName());

        echo "# Declared on same line:\n";
        [$a, $b] = [g(?), g(?)];
        var_dump((new ReflectionFunction($a))->getName(), (new ReflectionFunction($b))->getName());
    }

    f();
    C::m();

    echo "# From global scope:\n";
    var_dump((new ReflectionFunction(g(?)))->getName());
}

namespace pfa\instance_polymorphism {
    echo "# instance_polymorphism\n";
    class P {
        public function m(string $a): void {
            echo __METHOD__, PHP_EOL;
            var_dump($a);
        }


        public function get() {
            /* The method is resolved before creating the PFA, and captured by the
             * PFA. We use the signature of the resolved method. */
            return $this->m(?);
        }
    }

    class C extends P {
        public function m(string|array $b): void {
            echo __METHOD__, PHP_EOL;
            var_dump($b);
        }
    }

    for ($i = 0; $i < 2; $i++) {
        (new P())->get()(a: 'a');
        (new C())->get()(b: []);
    }
}

namespace pfa\static_polymorphism {
    echo "# static_polymorphism\n";
    class P {
        public static function m(string $a): void {
            echo __METHOD__, PHP_EOL;
            var_dump($a);
        }


        public static function get() {
            /* The method is resolved before creating the PFA, and captured by the
             * PFA. We use the signature of the resolved method. */
            return static::m(?);
        }
    }

    class C extends P {
        public static function m(string|array $b): void {
            echo __METHOD__, PHP_EOL;
            var_dump($b);
        }
    }

    for ($i = 0; $i < 2; $i++) {
        P::get()(a: 'a');
        C::get()(b: []);
    }
}

namespace pfa\invokable {
    echo "# invokable\n";
    class C {
        public function __invoke(int $a, object $b): C {
            var_dump($a, $b);
            return $this;
        }
    }

    $c = new C();
    $f = $c(?, ...);

    echo (string) new ReflectionFunction($f), "\n";

    $f = $c(?, new stdClass);

    echo (string) new ReflectionFunction($f), "\n";

    $f(1);
}

namespace pfa\static_method_001 {
    echo "# static_method_001\n";
    class Foo {
        public static function method($a, $b) {
            printf("%s\n", __METHOD__);
        }
    }

    $foo = Foo::method(new stdClass, ...);

    $bar = $foo(new stdClass, ...);

    $bar();
}

namespace pfa\clone {
    echo "# clone\n";
    class C {
        public function __construct(
            public mixed $a,
            public mixed $b,
        ) { }
    }

    $clone = clone(?);
    var_dump($clone(new C(1, 2)));

    $clone = clone(...);
    var_dump($clone(new C(3, 4)));

    $clone = clone(new C(5, 6), ?);
    var_dump($clone(['a' => 7]));

    $clone = clone(?, ['a' => 8]);
    var_dump($clone(new C(9, 10)));
}

namespace pfa\deprecated {
    echo "# deprecated\n";
    #[Deprecated] function f($a) {
    }

    $f = f(?);
    $f(1);
}

namespace pfa\construct_throw_arg_leak {
    echo "# construct_throw_arg_leak\n";
    class Obj {}

    function typed(int $a, $b, $c) {}
    try {
        typed([1, 2, 3], new Obj(), ?);
    } catch (\TypeError $e) {
        echo $e::class, "\n";
    }

    function typed2($a, int $b, $c, $d) {}
    try {
        typed2(new Obj(), [1, 2], new Obj(), ?);
    } catch (\TypeError $e) {
        echo $e::class, "\n";
    }

    function one($a) {}
    try {
        one(new Obj(), new Obj(), ?);
    } catch (\ArgumentCountError $e) {
        echo $e::class, "\n";
    }

    echo "OK\n";
}

namespace pfa\default_arg_scope {
    echo "# default_arg_scope\n";
    if (getenv('A')) {
        /* Relative class references are never resolved at compile time on traits */
        trait T {
            static function f($a, $b = self::VAL) {
                var_dump($b);
            }
        }
        trait U {
            static function g($a, $b = parent::VAL) {
                var_dump($b);
            }
        }
    }

    class C {
        const VAL = 'C';
        use T;
    }

    class D extends C {
        const VAL = 'D';
        use U;
    }

    C::f(0);
    D::f(0);
    C::f(?, ...)(0);
    D::f(?, ...)(0);

    D::g(0);
    D::g(?, ...)(0);
}

namespace pfa\hook {
    echo "# hook\n";
    class C {
        public $a {
            set($value) { var_dump($value); }
        }
    }

    class D extends C {
        public $a {
            set($value) {
                $f = parent::$a::set(?);
            }
        }
    }

    $d = new D();
    $d->a = 1;
}
