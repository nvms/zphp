<?php
// only Throwable objects can be thrown

class Foo {}

function gen() { yield 1; }

foreach ([1, "str", null, [1], new Foo, gen(), fn() => 1] as $value) {
    try {
        throw $value;
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), " (line ", $e->getLine(), ")\n";
    }
}

function rethrows() {
    try {
        throw new Foo;
    } finally {
        echo "finally ran\n";
    }
}
try {
    rethrows();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

try {
    try {
        exit_through();
    } finally {
        echo "outer finally\n";
    }
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), "\n";
}
function exit_through() { throw new Exception("real"); }

try {
    echo "before exit\n";
    exit(0);
} finally {
    echo "finally after exit\n";
}
