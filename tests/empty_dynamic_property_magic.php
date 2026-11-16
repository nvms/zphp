<?php
// empty() on a dynamic property name asks __isset, then __get, as for a literal name
class C {
    function __isset($n) { $GLOBALS['seen'] = $n; return true; }
    function __get($n) { $GLOBALS['got'] = $n; return 0; }
}
$o = new C;
$name = 'foo';
var_dump(empty($o->$name));
var_dump($seen ?? 'unset', $got ?? 'unset');
var_dump(isset($o->bar));
var_dump($seen);
function f() {
    $o = new C;
    $n = 'baz';
    var_dump(empty($o->$n));
    var_dump($GLOBALS['seen'], $GLOBALS['got']);
}
f();
var_dump($seen, $got);

class D {
    public $set = 'x';
    public $zero = 0;
    function __isset($n) { echo "__isset($n)\n"; return $n === 'magic'; }
    function __get($n) { echo "__get($n)\n"; return ''; }
}
$d = new D;
foreach (['set', 'zero', 'magic', 'missing'] as $p) {
    var_dump(empty($d->$p));
    var_dump(empty($d->{$p . ''}));
}
