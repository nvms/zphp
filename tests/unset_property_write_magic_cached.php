<?php
// a write site that already stored into a declared property must still
// call __set once the property is unset
class A {
    public $p = 1;
    public int $t = 2;
    public function __set($n, $v) { echo "__set($n, ", var_export($v, true), ")\n"; }
    public function __get($n) { echo "__get($n)\n"; return 10; }
}
function w($a, $v) { $a->p = $v; }
function wt($a, $v) { $a->t = $v; }
function inc($a) { $a->p++; }
function cat($a) { $a->p .= "x"; }

$a = new A;
w($a, 'first');
wt($a, 3);
inc($a);
cat($a);
var_dump($a);
unset($a->p, $a->t);
w($a, 'second');
wt($a, 4);
inc($a);
cat($a);
var_dump($a);

class C extends ArrayObject {
    public $p = 'object property';
}
function access_p($ao) {
    var_dump(isset($ao->p));
    var_dump($ao->p);
    $ao->p = $ao->p . '.changed';
    var_dump($ao->p);
}
$ao = new C(['p' => 'array element']);
$ao->setFlags(ArrayObject::ARRAY_AS_PROPS);
access_p($ao);
unset($ao->p);
access_p($ao);
unset($ao->p);
access_p($ao);
var_dump($ao);
