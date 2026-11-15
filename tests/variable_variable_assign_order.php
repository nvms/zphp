<?php
// ${expr} = value evaluates the name expression first, $$name reads the
// name variable when the assignment runs
function f() { echo "in f()\n"; return "name"; }
function g() { echo "in g()\n"; return "value"; }
${f()} = g();
var_dump($name);
$n = "first";
$$n = ($n = "second");
var_dump($second ?? null, $first ?? null);
${"a" . f()} = 1;
var_dump($aname);
