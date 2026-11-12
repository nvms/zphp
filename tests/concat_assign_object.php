<?php
class Tmp { public function __toString() { return "abc"; } }
$tmp = new Tmp;
$tmp .= $tmp;
var_dump($tmp);
$t2 = new Tmp;
$s = "x";
$s .= $t2;
var_dump($s);
$t3 = new Tmp;
$t3 .= "y";
var_dump($t3);
function f() { $o = new Tmp; $o .= $o; return $o; }
var_dump(f());
class H { public $p; }
$h = new H; $h->p = new Tmp; $h->p .= "z"; var_dump($h->p);
$arr = [new Tmp]; $arr[0] .= "w"; var_dump($arr);
