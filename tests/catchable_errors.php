<?php

// undefined function
try {
    nonexistent_function();
} catch (Error $e) {
    echo "1: " . $e->getMessage() . "\n";
}

// undefined method
class Foo {}
try {
    $f = new Foo();
    $f->noSuchMethod();
} catch (Error $e) {
    echo "2: " . $e->getMessage() . "\n";
}

// undefined static method
try {
    Foo::noSuchStaticMethod();
} catch (Error $e) {
    echo "3: " . $e->getMessage() . "\n";
}

// catch with Throwable
try {
    another_missing();
} catch (Throwable $e) {
    echo "4: " . get_class($e) . "\n";
}

// nested catch
function outer() {
    try {
        inner();
    } catch (Error $e) {
        return "caught in outer: " . $e->getMessage();
    }
}

function inner() {
    no_such_func();
}

echo "5: " . outer() . "\n";
