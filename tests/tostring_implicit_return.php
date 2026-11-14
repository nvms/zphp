<?php
// __toString has an implicit string return type, so falling off its end is
// "none returned"

class NoneTest {
    function __toString() {}
}

class NullTest {
    function __toString() { return null; }
}

class Ok {
    function __toString() { return "ok"; }
}

foreach ([new NoneTest, new NullTest, new Ok] as $o) {
    try {
        echo (string) $o, "\n";
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}

function test($y = new NoneTest > '') {
    return $y;
}
try {
    test();
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

var_dump((string) (new ReflectionMethod('NoneTest', '__toString'))->getReturnType());
