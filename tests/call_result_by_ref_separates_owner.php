<?php
$q = [3,2,1];
function g() { global $q; return $q; }
sort(g()); print_r($q);
class O { public $p = [3,2,1]; function get() { return $this->p; } }
$o = new O; sort($o->get()); print_r($o->p);
function f() { static $a = [3,2,1]; return $a; }
sort(f()); print_r(f());
function h() { static $a = [3,2,1]; $b = $a; return $b; }
sort(h()); print_r(h());
