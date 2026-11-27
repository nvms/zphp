<?php
// `$o->p = &$v` on a property the object doesn't have creates it through the
// write fetch: deprecated, or refused for a class that forbids it
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "error $no: $msg\n";
    return true;
});

class A {
    public $declared;
}
#[AllowDynamicProperties]
class B {}

$a = new A;
$v = 1;
$a->x = &$v;
$a->y = &$a->declared;
$a->x = &$v;
$a->declared = &$v;
var_dump($a);

$b = new B;
$b->x = &$v;
var_dump($b);

$s = new stdClass;
$s->x = &$v;
var_dump($s);

readonly class R {
    public int $p;
}
$r = new R;
try {
    $r->q = &$v;
} catch (Error $err) {
    echo get_class($err), ": ", $err->getMessage(), "\n";
}
