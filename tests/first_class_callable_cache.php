<?php
// php 8.6 shares one Closure per function named in a first-class callable
// for the rest of the request; method callables are still made each time
function f() { return 1; }
class C { function m() {} static function s() {} }
$a = strlen(...);
$b = strlen(...);
var_dump($a === $b);
var_dump(f(...) === f(...));
var_dump(\strlen(...) === strlen(...));
$o = new C;
var_dump($o->m(...) === $o->m(...));
var_dump(C::s(...) === C::s(...));
var_dump('strlen'(...) === strlen(...));
function g() { return strlen(...); }
var_dump(g() === g());
unset($a, $b);
var_dump(g()(...) === g());
echo spl_object_id(strlen(...)) === spl_object_id(strlen(...)) ? "same\n" : "diff\n";
var_dump(STRLEN(...) === strlen(...));
var_dump('C::s'(...) === 'C::s'(...));
var_dump("strlen"(...) === strlen(...));
