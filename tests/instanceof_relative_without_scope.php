<?php
// instanceof self, parent or static with no class to name is an Error when
// the left side is an object

$fn = function ($v) {
    foreach (['self', 'parent', 'static'] as $kind) {
        try {
            var_dump(match ($kind) {
                'self' => $v instanceof self,
                'parent' => $v instanceof parent,
                'static' => $v instanceof static,
            });
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
};
$fn(new stdClass);
$fn(42);

class A {
    function test($v) {
        var_dump($v instanceof self, $v instanceof static);
    }
}
class B extends A {
    function test2($v) { var_dump($v instanceof parent); }
}
(new A)->test(new B);
(new B)->test2(new B);
$bound = Closure::bind($fn, null, A::class);
$bound(new A);
