<?php
// __isset that writes the property: `??` and empty() read what it wrote
// instead of calling __get (php 8.6, GH-12695)
#[AllowDynamicProperties]
class A {
    public function __get($n) { echo "__get($n)\n"; return 'from get'; }
    public function __isset($n) {
        echo "__isset($n)\n";
        if ($n !== 'none') $this->$n = $GLOBALS['next'];
        return true;
    }
}
$GLOBALS['next'] = 123;
$a = new A;
var_dump($a->foo ?? 'fallback');
$GLOBALS['next'] = null;
$a = new A;
var_dump($a->bar ?? 'fallback');
$GLOBALS['next'] = 0;
$a = new A;
var_dump(empty($a->baz));
$GLOBALS['next'] = 'x';
$a = new A;
var_dump(empty($a->qux));
var_dump($a->none ?? 'fallback');
var_dump(empty($a->none));

class B {
    public int $x = 99;
    private $hidden = 'secret';
    public function __get($n) { echo "B::__get($n)\n"; return 1; }
    public function __isset($n) { echo "B::__isset($n)\n"; if ($n === 'x') $this->x = 7; return true; }
}
$b = new B;
unset($b->x);
var_dump($b->x ?? 'fallback');
var_dump($b->hidden ?? 'fallback');

class C {
    public $prop;
    public function __isset($name) {
        global $obj;
        $obj = null;
        $this->prop = 'materialised';
        return true;
    }
}
$obj = new C();
unset($obj->prop);
var_dump($obj->prop ?? 'fb');
