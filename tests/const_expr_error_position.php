<?php
// an error raised while a class constant or a property default is evaluated
// is reported at the expression, and its trace starts with php's
// "[constant expression]" frame at the code that needed the value; a
// constant that only names a global constant is looked up at the access

class C {
    const c1 = D::hello;
    const c2 = self::missing;
    const c3 = NONEXISTENT;
    const c4 = NONEXISTENT + 1;
    const c5 = [1][2];
}
class Q {
    public $q = UNDEFINED_GLOBAL;
}
class P {
    public $p = E::x;
}
enum En: string { const Bar = NOPE; }

function show(Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), ' at line ', $e->getLine(), "\n";
    foreach ($e->getTrace() as $frame) {
        echo '  ', $frame['function'], ' line ', $frame['line'] ?? '-', "\n";
    }
}

function access(string $what) {
    return constant($what);
}

foreach (['C::c1', 'C::c2', 'C::c3', 'C::c4', 'En::Bar'] as $name) {
    try {
        access($name);
    } catch (Error $e) {
        show($e);
    }
}
try {
    echo C::c1;
} catch (Error $e) {
    show($e);
}
var_dump(@C::c5);
try {
    new P;
} catch (Error $e) {
    show($e);
}
try {
    new Q;
} catch (Error $e) {
    show($e);
}
