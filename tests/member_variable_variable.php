<?php
// a member name may be a variable variable: $o->$$name and $o->${expr}
class C { public $p = 'prop'; public $q; function a() { return $this; } function b() { return 'b!'; } }
$o = new C; $a = 'p'; $b = 'a'; $n = 'q';
var_dump($o->$$b, $o->{$$b});
$o->${'n'} = 'set'; var_dump($o->q);
$m = 'b'; $x = 'm'; var_dump($o->$$x());
$a = 'a'; var_dump($o->$$b()->$$x());
$null = null; var_dump($null?->$$b);
function f() { echo "in f\n"; return 'name'; } function g() { echo "in g\n"; return 'v'; }
$name = 'dyn'; $s = new stdClass; $s->${f()} = g(); var_dump($s);
