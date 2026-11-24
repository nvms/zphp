<?php
// php 8.6 keeps a static closure that captures nothing and has no static
// variables, made in a function, and hands the same one back each time the
// site runs for the same called scope
function stateless() { return static function () { return 1; }; }
function plain() { return function () {}; }
function captures($x) { return static function () use ($x) { return $x; }; }
function statics() { return static function () { static $n = 0; return ++$n; }; }
function arrow() { return static fn($a) => $a * 2; }
function arrowCapture($b) { return static fn($a) => $a * $b; }
function nested() { return static function () { return static fn() => 3; }; }

var_dump(stateless() === stateless());
var_dump(plain() === plain());
var_dump(captures(1) === captures(1));
var_dump(statics() === statics());
var_dump(arrow() === arrow());
var_dump(arrowCapture(2) === arrowCapture(2));
var_dump(nested()() === nested()());
var_dump(nested() === nested());

// the main script's closures aren't kept
$make = [];
for ($i = 0; $i < 2; $i++) $make[] = static function () {};
var_dump($make[0] === $make[1]);

class A {
    function get() { return static function () { return static::class; }; }
    static function make() { return static fn() => static::class; }
}
class B extends A {}
$a = new A;
var_dump($a->get() === $a->get());
var_dump((new A)->get() === $a->get());
var_dump((new B)->get() === $a->get());
var_dump((new B)->get() === (new B)->get());
var_dump(A::make() === A::make(), A::make()(), B::make()());
var_dump(B::make() === B::make());

// the kept closure survives what held it
$first = stateless();
$id = spl_object_id($first);
unset($first);
var_dump(spl_object_id(stateless()) === $id);

// each fetch of the kept closure holds its own reference
for ($i = 0; $i < 3; $i++) {
    $cb = A::make();
    echo $cb(), ' ', B::make()(), "\n";
}
$before = memory_get_usage();
for ($i = 0; $i < 1000; $i++) { $f = stateless(); $f(); }
var_dump(memory_get_usage() - $before < 1024);
