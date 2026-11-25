<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\magic_001 {
    echo "# magic_001\n";
    class Foo {
        public function __call($method, $arguments) {
            printf("%s::%s\n", __CLASS__, $method);

            var_dump(...$arguments);
        }
    }

    $foo = new Foo;

    $bar = $foo->method(?);

    echo (string) new ReflectionFunction($bar);

    try {
        $bar();
    } catch (Error $ex) {
        printf("%s: %s\n", $ex::class, $ex->getMessage());
    }

    $bar(1, 2);
    $bar(1);

    $bar = $foo->method(?, ...);

    echo (string) new ReflectionFunction($bar);

    $bar(10);
    $bar(10, 20);

    $bar = $foo->method(new Foo, ...);

    echo (string) new ReflectionFunction($bar);

    $bar(100);
}

namespace pfa\magic_002 {
    echo "# magic_002\n";
    class Foo {
        public static function __callStatic($method, $arguments) {
            printf("%s::%s\n", __CLASS__, $method);

            var_dump(...$arguments);
        }
    }

    $bar = Foo::method(?);

    echo (string) new ReflectionFunction($bar);

    $bar(1);
    $bar(1, 2);

    $bar = Foo::method(?, ...);

    echo (string) new ReflectionFunction($bar);

    $bar(10);
    $bar(10, 20);

    $bar = Foo::method(new Foo,...);

    echo (string) new ReflectionFunction($bar);

    $bar(100);
}

namespace pfa\magic_003 {
    echo "# magic_003\n";
    class Foo {
        static function __callStatic($name, $args) {}
    }
    Foo::method(?);

    echo "OK";
}

namespace pfa\magic_004 {
    echo "# magic_004\n";
    class Foo {
        static function __callStatic($name, $args) {}
    }
    $a = Foo::method(?);
    (void)Foo::method(?);

    echo "OK";
}

namespace pfa\magic_005 {
    echo "# magic_005\n";
    class Foo {
        function __call($name, $args) {
        }
    }
    $foo = new Foo;
    $bar = $foo->method(?);
    var_dump($bar);
}

namespace pfa\magic_006 {
    echo "# magic_006\n";
    class Foo {
        function __call($name, $args) {
            var_dump($args);
        }
    }
    $foo = new Foo;
    $bar = $foo->method(1,...);
    $bar(2);
}
