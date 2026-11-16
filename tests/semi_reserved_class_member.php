<?php
// `class` names a method and a static property like any semi-reserved word;
// only a bare ::class is the class name
class Obj {
    static $class = 'the property';
    static function class() { return __METHOD__; }
    function __call($n, $a) { return "call $n"; }
}
var_dump(Obj::class);
var_dump(Obj::class());
var_dump(Obj::$class);
var_dump(isset(Obj::$class), Obj::$class ?? 'none');
Obj::$class = 'changed';
var_dump(Obj::$class);
$n = 'class';
var_dump(Obj::$$n);
var_dump(Obj::{$n}());
$c = 'Obj';
var_dump($c::$class, $c::class());
var_dump((new Obj)->class());
