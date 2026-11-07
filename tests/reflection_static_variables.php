<?php
// getStaticVariables lists what a function, closure or method declares static,
// with the initial values before the declaration runs
function counter() { static $n = 0; static $label = "x"; $n++; return $n; }
var_dump((new ReflectionFunction('counter'))->getStaticVariables());
counter(); counter();
var_dump((new ReflectionFunction('counter'))->getStaticVariables());
$y = 5;
$f = function () use ($y) { static $z = [1]; return $y; };
var_dump((new ReflectionFunction($f))->getStaticVariables());
class C { function m() { static $q = 1; return ++$q; } }
var_dump((new ReflectionMethod('C', 'm'))->getStaticVariables());
