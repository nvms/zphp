<?php
// calling [$object, 'method'] or an invokable object through a variable
// passes by-reference arguments and binds a returned reference, as
// $object->method() does

class C {
    public function set(&$a, $value) { $a = $value; }
    public function &pick(array &$list, $key) { return $list[$key]; }
    public function __invoke(&$counter) { $counter++; return 'invoked'; }
    private function hidden() { return 'hidden'; }
    public function __call($name, $args) { return "__call($name)"; }
}

class Ref {
    public function &__invoke(&$a) { return $a; }
}

$o = new C;
$a = 1;
$set = [$o, 'set'];
$set($a, 9);
var_dump($a);

$list = ['x' => 1, 'y' => 2];
$pick = [$o, 'pick'];
$slot =& $pick($list, 'y');
$slot = 'changed';
var_dump($list);

$n = 0;
var_dump($o($n), $o($n), $n);

$r = new Ref;
$v = 1;
$alias =& $r($v);
$alias = 5;
var_dump($v);

var_dump([$o, 'hidden'](), [$o, 'missing'](1));

foreach ([[$o, 'nope', 1], new stdClass, [new Ref]] as $callable) {
    try {
        $callable();
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

class Hidden {
    private function __invoke() { return "called anyway"; }
}
$h = @new Hidden;
var_dump($h());
try {
    $h->__invoke();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
