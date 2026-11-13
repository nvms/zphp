<?php
// a reference to a property __get answers for: taking one binds a copy of
// what __get returned (with php's notice for a by-value result), and
// assigning one is an Error

class ByValue {
    public $q = 3;
    public function __get($name) {
        echo "__get($name)\n";
        return $this->q;
    }
}

$a = new ByValue;
$c =& $a->whatever;
$c = "long";
print_r($a);
echo "\n";

$b = "short";
try {
    $a->whatever =& $b;
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
print_r($a);
echo "\n";

class ByRef {
    private $x = 1;
    public function &__get($name) {
        echo "&__get($name)\n";
        return $this->x;
    }
}
$t = new ByRef;
$y = 5;
try {
    $t->x =& $y;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$r =& $t->x;
$r = 9;
var_dump($t);

class ReturnsObject {
    public function __get($name) {
        return new stdClass;
    }
}
$o = new ReturnsObject;
$ref =& $o->anything;
var_dump($ref);

// declared, visible properties are bound as usual
class Plain {
    public $p = 1;
    public function __get($name) {
        echo "not called\n";
    }
}
$p = new Plain;
$v = 2;
$p->p =& $v;
$v = 3;
var_dump($p->p);

class Hooked {
    public $prop = 0 {
        &get {
            echo __METHOD__, "\n";
            return $this->prop;
        }
    }
}
$h = new Hooked;
try {
    $h->prop = &$ref2;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
