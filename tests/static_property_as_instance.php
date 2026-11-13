<?php
// a static property named through an object: a notice and a dynamic
// property when the scope can see it, php's access error when it can't

#[AllowDynamicProperties]
class C {
    public static $x = 'C::$x';
    protected static $y = 'C::$y';

    function own() {
        $this->y = 'own';
        return $this->y;
    }
}

$c = new C;
var_dump(isset($c->x));
$c->x = 1;
var_dump($c->x);
for ($i = 0; $i < 2; $i++) {
    // every read notices, not just the first
    echo $c->x, "\n";
}
unset($c->x);
var_dump(isset($c->x), C::$x);
var_dump($c->own());

foreach (['read', 'write', 'unset', 'ref'] as $op) {
    try {
        switch ($op) {
            case 'read': echo $c->y; break;
            case 'write': $c->y = 1; break;
            case 'unset': unset($c->y); break;
            case 'ref': $c->y = &$r; break;
        }
    } catch (Error $e) {
        echo $op, ": ", $e->getMessage(), "\n";
    }
}
var_dump(isset($c->y));

// with the magic method present, php stays silent and calls it
class M {
    protected static $p = 1;
    function __get($n) { return "__get($n)"; }
    function __set($n, $v) { echo "__set($n)\n"; }
    function __unset($n) { echo "__unset($n)\n"; }
}
$m = new M;
var_dump($m->p);
$m->p = 2;
unset($m->p);

// an ancestor's private static is just a dynamic name
#[AllowDynamicProperties]
class P {
    private static $q = 1;
}
class K extends P {}
$k = new K;
$k->q = 5;
var_dump($k->q);
