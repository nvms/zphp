<?php
// ArrayObject's property handlers: with ARRAY_AS_PROPS a property that isn't
// there is an element of the storage, reached through offsetGet() and the
// rest, never a subclass's magic methods; without it, properties are
// ordinary ones, private ones included
class UsesMagic extends ArrayObject {
    public $declared = 'declared';
    private $hidden = 'hidden';
    function __get($n) { echo "__get($n)\n"; return 'magic'; }
    function __set($n, $v) { echo "__set($n)\n"; }
    function __isset($n) { echo "__isset($n)\n"; return true; }
    function __unset($n) { echo "__unset($n)\n"; }
    static function peek($o) { return $o->hidden; }
}

$ao = new UsesMagic(['a' => 1, 'n' => null], ArrayObject::ARRAY_AS_PROPS);
var_dump($ao->a, $ao->declared, isset($ao->a), isset($ao->n), isset($ao->zz), empty($ao->a));
$ao->b = 2;
unset($ao->a);
var_dump($ao->getArrayCopy());
var_dump($ao->missing);
var_dump($ao->hidden, UsesMagic::peek($ao));
var_dump(property_exists($ao, 'b'), property_exists($ao, 'declared'));

$ao->setFlags(0);
var_dump($ao->b);
$ao->c = 3;
var_dump(isset($ao->c), $ao->getArrayCopy());

class Plain extends ArrayObject {
    private $x = 'secret';
    public $p = 'object property';
    static function go($c) { var_dump($c->x); }
}
$c = new Plain(['x' => 'public', 'p' => 'element']);
$c->setFlags(ArrayObject::ARRAY_AS_PROPS);
Plain::go($c);
var_dump($c->x, $c->p);
unset($c->p);
var_dump($c->p);
unset($c->p);
var_dump(isset($c->p));
$c->setFlags(0);
Plain::go($c);
try {
    var_dump($c->x);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    $c->x = 1;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

class Offsets extends ArrayObject {
    function offsetGet($k): mixed { echo "offsetGet($k)\n"; return parent::offsetGet($k); }
    function offsetSet($k, $v): void { echo "offsetSet($k)\n"; parent::offsetSet($k, $v); }
    function offsetExists($k): bool { echo "offsetExists($k)\n"; return parent::offsetExists($k); }
    function offsetUnset($k): void { echo "offsetUnset($k)\n"; parent::offsetUnset($k); }
}
$o = new Offsets(['k' => 'v'], ArrayObject::ARRAY_AS_PROPS);
var_dump($o->k, isset($o->k));
$o->m = 1;
unset($o->m);
var_dump($o->getArrayCopy());
