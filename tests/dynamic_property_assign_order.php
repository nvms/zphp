<?php
// a dynamic property name is evaluated once, before the value assigned
function f() { echo "f\n"; return "n"; }
function g() { echo "g\n"; return 1; }
$s = new stdClass;
$s->{f()} = g();
$a = [];
$a[f()] = g();
$s->n = 'a';
$s->{f()} .= g();
var_dump($s->n);
$s->k = 1;
$k = 'k';
$s->$k += 5;
var_dump($s->k);
$s->{f()} ??= g();
