<?php
// a parameter default naming a constant resolves it as a constant: through
// `use const`, else in the namespace (falling back to the global one), and
// never through a class import

namespace Foo {
    const CONSTANT = 'Foo\CONSTANT';
    const OTHER = 'Foo\OTHER';
}

namespace NS {
    use const Foo\CONSTANT;
    use const Foo\OTHER as O;
    use Foo\Bar;

    const LOCAL = 'NS\LOCAL';

    function f($a = CONSTANT, $b = O, $c = PHP_INT_SIZE, $d = LOCAL, $e = [CONSTANT, O]) {
        var_dump($a, $b, $c, $d, $e);
    }

    function g($x = Bar) {
        return $x;
    }

    f();
    foreach ((new \ReflectionFunction('NS\f'))->getParameters() as $p) {
        var_dump($p->getDefaultValueConstantName());
    }
    var_dump((new \ReflectionFunction('NS\g'))->getParameters()[0]->getDefaultValueConstantName());
    try {
        g();
    } catch (\Error $e) {
        echo $e->getMessage(), "\n";
    }
}

namespace {
    use const Foo\CONSTANT;

    class A {
        public function foo($p1 = \Foo\CONSTANT, $p2 = Foo\CONSTANT, $p3 = CONSTANT) {
        }
    }

    echo str_replace(__FILE__, 'FILE', (string) new ReflectionMethod('A', 'foo'));
}
