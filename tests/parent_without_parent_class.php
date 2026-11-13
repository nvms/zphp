<?php
// parent:: in a class with no parent names the missing parent, not a
// missing scope; outside any class it is the missing scope
class A {
    public static function make($x = new parent) {
        return $x;
    }
}

function outside($x = new self) {
    return $x;
}

foreach (['A::make', 'outside'] as $f) {
    try {
        $f();
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
