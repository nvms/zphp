<?php
// a binary operation reads a variable operand when it runs, after the right
// side wrote it
$a = "bad"; $b = "good";
echo $a . ($a = $b), "\n";
function foo() { global $a; $a = "late"; return "!"; }
$a = "early"; echo $a . foo(), "\n";
$x = 1; var_dump($x - ($x++), $x - (++$x), $x + ($x = 10), $x . ($x .= "y"));
function local() { $x = 1; $y = $x - ($x++); $z = $x * ($x = 5); return [$y, $z]; }
var_dump(local());
$s = [1]; var_dump($s + ($s = [2, 3]));
