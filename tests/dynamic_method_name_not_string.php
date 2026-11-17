<?php
// a method name computed at run time that isn't a string is a catchable Error
class Foo {
    public function __call($a, $b) { return "call $a"; }
}
$o = new Foo;
foreach ([null, 42, [], 1.5] as $name) {
    try {
        $o->$name();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
    try {
        $o->$name(...[1, 2]);
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
echo $o->{'x'}(), "\n";
