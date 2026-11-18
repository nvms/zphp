<?php
// getClosureUsedVariables() and getStaticVariables() give a variable a
// closure uses by reference as the reference itself
$one = 1; $f = function () use (&$one) { $one++; };
$vars = (new ReflectionFunction($f))->getClosureUsedVariables(); var_dump($vars);
$vars["one"] = 10; $f(); var_dump($one);
var_dump((new ReflectionFunction($f))->getStaticVariables());
