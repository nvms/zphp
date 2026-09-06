<?php
class B { public $x = 1; }
class C { static function change(&$x) { $x = 9; } function __construct(&$x) { $x=8; } }
$b=new B; $m='change'; $c='C';
C::$m($b->x); echo $b->x,"\n";
$b->x=1; $c::$m($b->x); echo $b->x,"\n";
$b->x=1; $c::$m(...[], x: $b->x); echo $b->x,"\n";
$b->x=1; new C($b->x); echo $b->x,"\n";
$b->x=1; new $c($b->x); echo $b->x,"\n";
$b->x=1; new C(...[], x:$b->x); echo $b->x,"\n";
$b->x=1; new $c(...[$b->x]); echo $b->x,"\n";
