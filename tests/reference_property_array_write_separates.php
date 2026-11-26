<?php
// a write into a property bound to a reference separates the reference set
// from a value copy of its array, as a write through any reference does
class G { public $ref; }
$g = new G();
$inner = [1, [5]];
$g->ref = &$inner;
$copy = $inner;
$g->ref['k'] = 3;
$g->ref[0] .= 'x';
$g->ref[1][] = 6;
$g->ref[] = 7;
var_dump($copy, $inner, $g);

$h = new G();
$h->ref = [1];
$r = &$h->ref;
$c2 = $r;
$h->ref[] = 2;
$r[] = 3;
var_dump($c2, $r, $h);

function f($a) { global $g; $g->ref[] = 4; var_dump(count($a)); }
f($inner);

class S { public static $p; public $q; }
$x = [1];
S::$p = &$x;
$c = $x;
S::$p[] = 2;
S::$p['k'] = 3;
var_dump($c, $x);

$o = new S;
$y = [1, 2];
$o->q = &$y;
$c = $y;
unset($o->q[0]);
$z = 9;
$o->q[5] = &$z;
$o->q[1]++;
var_dump($c, $y);
