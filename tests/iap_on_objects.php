<?php
// reset(), next(), prev(), end(), current() and key() on an object walk its
// property table (deprecated): declared slots in order, an uninitialized
// one skipped as the pointer passes it, then dynamic properties
class P {
    public int $a;
    public int $b = 2;
    protected $c = 3;
    private $d = 4;
    public $e = 5;
}
$o = new P;
$o->dyn = 6;
var_dump(key($o), current($o));
while (($v = next($o)) !== false) var_dump(key($o), $v);
var_dump(key($o), current($o));
var_dump(end($o), key($o));
var_dump(prev($o), key($o));
var_dump(reset($o), key($o));
var_dump(prev($o), key($o), current($o));

$e = new stdClass;
var_dump(reset($e), end($e), next($e), key($e));

class Undef { public int $x; }
$u = new Undef;
var_dump(key($u), current($u));
$u->x = 1;
var_dump(key($u), current($u));
reset($u);
var_dump(key($u), current($u));

$n = (object) ['10' => 'ten', 'k' => 'kay'];
var_dump(key($n), next($n), key($n));
