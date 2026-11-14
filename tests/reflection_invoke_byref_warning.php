<?php
// reflection calls a function taking a parameter by reference with a value
// the way internal code does: it warns and passes the value
set_error_handler(function ($no, $msg) { echo "warning: ", $msg, "\n"; });
class C {
    function __construct(&$x) { $x = "changed"; }
    function m(&$a, $b, &$c) { return "m"; }
    static function s(&$a) { return "s"; }
}
$x = "original";
$rc = new ReflectionClass('C');
$rc->newInstance($x);
var_dump($x);
$rc->newInstanceArgs([$x]);
var_dump($x);
$rc->newInstanceArgs(['x' => $x]);
function f(&$p, $q = 1) { return $p; }
$rf = new ReflectionFunction('f');
var_dump($rf->invoke(5));
var_dump($rf->invokeArgs([6]));
$v = 7;
var_dump($rf->invokeArgs([&$v]));
$bar = new stdClass;
$args = [1, &$bar];
$closure = function (int &$foo, object &$bar) { return $foo; };
var_dump((new ReflectionFunction($closure))->invokeArgs($args));
$rm = new ReflectionMethod('C', 'm');
$o = $rc->newInstanceWithoutConstructor();
var_dump($rm->invoke($o, 1, 2, 3));
var_dump($rm->invokeArgs($o, [1, 2, 3]));
var_dump((new ReflectionMethod('C', 's'))->invoke(null, 1));
