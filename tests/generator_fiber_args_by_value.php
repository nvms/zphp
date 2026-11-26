<?php
// Generator and Fiber methods take their arguments by value: an undefined
// variable passed to them warns and stays undefined
set_error_handler(function ($no, $msg, $file, $line) { echo "warning: $msg (line $line)\n"; return true; });

function h() { $x = yield 1; var_dump($x); yield 2; }
$h = h();
$h->current();
$h->send($undef1);
var_dump(array_key_exists('undef1', get_defined_vars()));

function gen() {
    $g = yield;
    try { $g->send($y); } catch (Error $e) { echo $e->getMessage(), "\n"; }
    var_dump(array_key_exists('y', get_defined_vars()));
}
$gen = gen();
$gen->send($gen);

$f = new Fiber(function ($a) { var_dump($a); $b = Fiber::suspend(); var_dump($b); });
$f->start($undef2);
$f->resume($undef3);
var_dump(array_key_exists('undef2', get_defined_vars()), array_key_exists('undef3', get_defined_vars()));
