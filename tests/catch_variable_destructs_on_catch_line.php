<?php
// a catch binding its exception to a variable destructs the old value on
// the catch's line (ZEND_CATCH)
class Foo {
    function __destruct() {
        echo "destruct at line ", debug_backtrace()[0]['line'], "\n";
    }
}
class Thrower {
    function __destruct() {
        throw new Exception("from destructor");
    }
}

function test() {
    $e = new Foo();
    try {
        throw new Exception("thrown");
    } catch (Exception $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
test();

function test2() {
    $e = new Thrower();
    try {
        throw new Exception("thrown");
    }
    catch (Exception $e) {
        echo "unreachable\n";
    }
}
try {
    test2();
} catch (Exception $e) {
    echo $e->getMessage(), " line ", $e->getTrace()[0]['line'], "\n";
}
