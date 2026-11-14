<?php
// constant() with a class constant: a missing class is the class lookup's
// error, a missing constant names the class as written

class A {
    const B = 1;
}

foreach (['A::B', 'a::B', 'A::B1', 'a::B1', '\A::B', '\A::C', 'NoSuchClass::X', '\NoSuchClass::X', 'NOPE'] as $name) {
    try {
        var_dump(constant($name));
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

spl_autoload_register(function ($c) {
    echo "autoload $c\n";
});
try {
    constant('Lazy::X');
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
