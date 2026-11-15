<?php
// an arrow function binds every variable its body names that the enclosing
// scope has, including ones known there only by name (global, static, a
// reference); one the scope doesn't have stays undefined in the arrow

$g = 5;
function viaGlobal() {
    global $g;
    $f = fn() => $g + 1;
    var_dump($f());
}
viaGlobal();

function viaStatic() {
    static $s = 2;
    $f = fn() => $s * 10;
    var_dump($f());
    $s++;
    var_dump($f(), (fn() => $s)());
}
viaStatic();

function viaReference() {
    $r = 1;
    $rr = &$r;
    $f = fn() => $rr;
    $r = 2;
    var_dump($f(), (fn() => $rr)());
}
viaReference();

function nested() {
    global $g;
    return (fn() => fn() => $g * 3)()();
}
var_dump(nested());

function missing() {
    $f = fn() => isset($nope) ? 'set' : 'unset';
    var_dump($f());
    $h = fn() => $nope2 ?? 'default';
    var_dump($h());
}
missing();

class K {
    public function m() {
        global $gg;
        $gg = 3;
        return (fn() => $gg * 2)();
    }
}
var_dump((new K)->m());
