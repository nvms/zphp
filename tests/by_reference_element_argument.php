<?php
// an element or property passed by reference is fetched for writing: missing
// containers and keys are created without warnings, arrays shared with copies
// are separated first, and $a[] appends the element it passes
function f(&$x) { $x = 9; }
$t = [1];
$copy = $t;
f($t[0]);
var_dump($copy[0], $t[0]);
$a = ['k' => [1]];
$copy = $a;
f($a['k'][5]);
f($a['n']['m']);
var_dump($a, $copy);
$n = null;
f($n[0]);
f($u['k']);
var_dump($n, $u);
$s = ['q' => false];
f($s['q']['z']);
var_dump($s);
$o = new stdClass;
f($o->list['a']);
f($o->p);
print_r($o);
class C { public array $items = []; public ?array $maybe = null; }
$c = new C;
f($c->items['x']);
f($c->maybe['y']);
print_r($c);
function g() {
    f($v[1][2]);
    var_dump($v);
    $w = null;
    try { f($w->x); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
g();
$data = [];
preg_match_all('/(\d)/', 'a1b2', $data['matches']);
var_dump(count($data['matches']));
$e = [];
f($e[]);
f($e[]);
$none = null;
f($none[]);
var_dump($e, $none);
foreach ([1, true, "s", 1.5, new stdClass] as $v) {
    try { f($v[]); } catch (Error $err) { echo $err->getMessage(), "\n"; }
}
$fn = "strlen";
try { $fn($e[]); } catch (Error $err) { echo $err->getMessage(), "\n"; }
