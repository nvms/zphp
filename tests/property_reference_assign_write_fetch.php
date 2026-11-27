<?php
// a property assigned by reference fetches its object for writing: a ${...}
// variable is created null without a warning, and only an object takes it
function t($f) { try { $f(); } catch (Throwable $e) { echo $e::class, ': ', $e->getMessage(), "\n"; } }
t(function () { $x = 1; $o->p =& $x; echo "a\n"; });
t(function () { $x = 1; $n = 'o'; $$n->p =& $x; echo "b\n"; var_dump($o); });
t(function () { $n = 'o'; $p = 'q'; $$n->$p =& $$n; echo "c\n"; var_dump($o); });
t(function () { $o = null; $x = 1; $o->p =& $x; });
t(function () { $o = 5; $x = 1; $o->p =& $x; });
t(function () { $a = []; $x = 1; $a[0]->p =& $x; var_dump($a); });
t(function () { $x = 1; $u[0]->p =& $x; var_dump($u); });
t(function () { $o = new stdClass; $o->p =& $o->q; var_dump($o); });
function f() {
    try { $o->p = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
    var_dump($o);
    $n = 'q';
    try { $$n->p = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
    var_dump($q);
    try { $$n->p =& $n; } catch (Error $e) { echo $e->getMessage(), "\n"; }
    try { $r->p =& $n; } catch (Error $e) { echo $e->getMessage(), "\n"; }
    var_dump($r);
}
f();
try { $o->p = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump($o);
