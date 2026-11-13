<?php
// function_exists() and get_defined_functions() know functions only, not
// methods or closures; the user list holds lowercased names

function foo() {}
function HelloWorld() {}

class C {
    function f1() {}
    static function f2() {}
}
$closure = function () {};
$arrow = fn() => 1;

var_dump(function_exists('foo'), function_exists('HELLOWORLD'), function_exists('\foo'));
var_dump(function_exists('C::f1'), function_exists('C::f2'), function_exists('strlen'), function_exists('Exception::getMessage'));

$functions = get_defined_functions();
$user = $functions['user'];
sort($user);
var_dump($user);
var_dump(in_array('strlen', $functions['internal']));
$methods = array_filter($functions['internal'], fn($name) => str_contains($name, '::'));
var_dump(count($methods));
