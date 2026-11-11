<?php
// a virtual property with only a set hook can't be read or isset; a hooked
// property can't be unset; a hooked property overriding a plain one is backed

class Test {
    public $_prop;
    public $prop {
        set { $this->_prop = $value; }
    }
    public $backed {
        get { return $this->backed; }
        set { $this->backed = $value; }
    }
    public function __unset($name) { echo "never reached\n"; }
}
$t = new Test;
$t->prop = 42;
var_dump($t->_prop);
foreach ([fn() => $t->prop, fn() => isset($t->prop), fn() => $t->prop ?? 'default'] as $f) {
    try { var_dump($f()); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
$t->backed = 1;
foreach (['prop', 'backed'] as $name) {
    try { unset($t->$name); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
var_dump($t->backed);

class A { public $prop; }
class B extends A {
    public $prop {
        set { echo "B::set\n"; }
    }
}
$b = new B;
$b->prop = 1;
var_dump($b->prop);

class Sub extends Test {}
$s = new Sub;
try { var_dump($s->prop); } catch (Error $e) { echo $e->getMessage(), "\n"; }
