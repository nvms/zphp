<?php
// a class constant name computed at run time must be a string
class Foo {
    public const BAR = 'bar';
}
$cls = 'Foo';
foreach ([null, 42, 1.5, true, [], new stdClass, 'BAR'] as $name) {
    try {
        var_dump(Foo::{$name});
    } catch (TypeError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
    try {
        var_dump($cls::{$name});
    } catch (TypeError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
try {
    var_dump(Nope::{42});
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
