<?php
// php answers 0 for x % -1, PHP_INT_MIN included, which a cpu traps on
$min = PHP_INT_MIN;
$m1 = -1;
var_dump($min % $m1, PHP_INT_MAX % $m1, 7 % $m1, -7 % $m1, 0 % $m1);
var_dump(PHP_INT_MIN % -1);
var_dump("-9223372036854775808" % "-1");
$x = PHP_INT_MIN;
$x %= -1;
var_dump($x);
function f($a, $b) { return $a % $b; }
for ($i = 0; $i < 3; $i++) var_dump(f(PHP_INT_MIN, -1));
var_dump(PHP_INT_MIN / -1, intdiv(PHP_INT_MIN + 1, -1));
try { intdiv(PHP_INT_MIN, -1); } catch (ArithmeticError $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump(fmod(PHP_INT_MIN, -1));
