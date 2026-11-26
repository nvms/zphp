<?php
// `$class::m(...)` names the class by the variable's value (an object by its class)
class K {
    static function s($v = 'd') { return "K:$v"; }
    function m() { return static::class; }
}
class K2 extends K { static function s($v = 'd') { return "K2:$v"; } }
$c = 'K2';
$f = $c::s(...);
var_dump($f('x'), $f());
$o = new K2;
$g = $o::s(...);
var_dump($g('y'));
$n = 5;
try { $h = $n::s(...); } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
$u = 'Nope';
try { $h = $u::s(...); } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
$m = 'K';
try { $h = $m::m(...); var_dump($h()); } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
