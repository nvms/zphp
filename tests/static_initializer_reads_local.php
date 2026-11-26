<?php
// a static variable's initializer runs before the variable is bound to the
// static, so it reads the local variable of the same name
function foo() {
    $a = new stdClass();
    $a->n = 1;
    static $a = $a;
    var_dump($a);
    $a->n++;
}
foo();
foo();
function baz() {
    $x = [1];
    static $x = $x;
    $x[] = count($x) + 1;
    var_dump($x);
}
baz();
baz();
function undef() {
    static $u = $u ?? 'default';
    var_dump($u);
}
undef();
function rec($depth) {
    static $r = $depth < 2 ? rec($depth + 1) . "<$depth" : "deep$depth";
    return $r;
}
var_dump(rec(0), rec(5));
