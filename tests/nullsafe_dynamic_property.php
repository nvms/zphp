<?php
// a nullsafe fetch names its property with a variable or an expression
class P { public $x = 6; public $y = 7; }
$o = new P;
$n = "x";
$z = null;
function name($v) { echo "name $v\n"; return $v; }

var_dump($o?->$n);
var_dump($o?->{"y"});
var_dump($o?->{name("x")});
var_dump($z?->{name("never")});
var_dump($o?->$n ?? "default");
var_dump($o?->{"missing"} ?? "default");
var_dump(isset($o?->$n), isset($z?->$n));
var_dump($z?->$n->deeper);
$p = new P;
$p->x = $o;
var_dump($p?->$n?->{"y"});
