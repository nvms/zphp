<?php
namespace {
    const baz = 'global baz';
    const qux = 'global qux';
}

namespace foo\bar {
    const qux = 'foo\bar\qux';
}

namespace other {
    use const foo\bar\baz;
    use const foo\bar\qux;

    // only an unqualified name falls back to the global constant
    var_dump(\qux);
    var_dump(qux);
    var_dump(\foo\bar\qux);
    foreach ([fn() => baz, fn() => \foo\bar\baz, fn() => namespace\baz, fn() => bar\baz] as $f) {
        try {
            var_dump($f());
        } catch (\Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
    const local = 'other\local';
    var_dump(local, namespace\local, \other\local);
    var_dump(PHP_INT_SIZE, \PHP_INT_SIZE);
}
