<?php
// var_dump marks an element or property that a reference still shares
$a = [1, 2];
$r = &$a[0];
var_dump($a);
unset($r);
var_dump($a);
$x = 1;
$arr = [&$x, 2];
var_dump($arr);
$b = [1, 2, 3];
foreach ($b as &$v) {}
var_dump($b);
unset($v);
var_dump($b);
function f(&$p) { $p = 9; }
$c = [1];
f($c[0]);
var_dump($c);
$d = [1];
$d[] = &$d;
var_dump($d);
$e = ['k' => 1];
$copy = $e;
$rr = &$e['k'];
var_dump($copy, $e);
$g = [[1]];
$q = &$g[0][0];
var_dump($g);
$o = new stdClass;
$o->p = 1;
$o->q = 2;
$rp = &$o->p;
var_dump($o);
unset($rp);
var_dump($o);
