<?php
// a closure made outside an object has no $this: using it is php's Error,
// while isset($this) is false; binding an object gives it one
$f = fn() => $this->foo;
$g = function () { return $this; };
$h = function () { return isset($this) ? get_class($this) : 'no this'; };
foreach ([$f, $g] as $c) {
    try {
        var_dump($c());
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump($h());
class Box { public $foo = 'box foo'; }
var_dump(Closure::bind($h, new Box, Box::class)());
var_dump(Closure::bind($f, new Box, Box::class)());
$s = static function () { return isset($this); };
var_dump($s());
class Maker {
    function make() { return function () { return get_class($this); }; }
    static function makeStatic() { return function () { return isset($this); }; }
}
var_dump((new Maker)->make()());
var_dump(Maker::makeStatic()());
