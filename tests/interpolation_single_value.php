<?php
// a double-quoted string holding only one variable is that value as a string

$b = 1;
$a = "$b";
var_dump($a);
$f = 1.5;
var_dump("$f", "{$f}");
$n = null;
var_dump("$n");
$arr = [5];
var_dump("$arr[0]", "{$arr[0]}");
class O { public $p = 7; function __toString() { return "o"; } }
$o = new O;
var_dump("$o->p", "$o", "{$o}");
$list = [1];
var_dump("$list");
$h = <<<EOT
$b
EOT;
var_dump($h);
