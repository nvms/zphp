<?php
// a static variable's initializer runs once: a static set to null later
// keeps null, and reflection's copy of the statics holds references to them
function h() { echo "h()\n"; return null; }
function f() {
    static $a = 1;
    static $b = h();
    static $c;
    var_dump($a, $b, $c);
    $a = null;
    $b = 5;
}
f();
f();
f();

function recursive($n) {
    static $x = inner();
    return $x;
}
function inner() {
    static $calls = 0;
    $calls++;
    if ($calls < 2) recursive(0);
    return $calls;
}
var_dump(recursive(1), recursive(2));

$closure = function () { static $n = 10; return ++$n; };
$closure();
$bound = $closure->bindTo(null);
var_dump($closure(), $bound(), $bound());

function g() {
    $r = new ReflectionFunction(__FUNCTION__);
    $before = $r->getStaticVariables()['v'];
    static $v = h();
    var_dump($v);
    $ref = &$r->getStaticVariables()['v'];
    $ref = $before ?? 'set through reflection';
}
g();
g();
