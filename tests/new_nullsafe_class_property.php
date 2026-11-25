<?php
// `new $obj?->prop` takes the class name from a nullsafe property read; a
// null object gives a null class name, which new refuses
class Bar {}
class Foo { public $bar = 'Bar'; public $name = 'bar'; }
$foo = new Foo();
var_dump(new $foo?->bar);
var_dump(new $foo?->bar());
$foo = null;
try {
    var_dump(new $foo?->bar);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
