<?php
// Closure::getCurrent() returns the closure that is running, so an anonymous
// function can call itself; anything else throws
$fact = function (int $n) { return $n <= 1 ? 1 : $n * Closure::getCurrent()($n - 1); };
var_dump($fact(5));
$x = 3;
$counter = function () use ($x) { $self = Closure::getCurrent(); var_dump($self instanceof Closure, $self === null); return $x; };
var_dump($counter());
$arrow = fn() => Closure::getCurrent() instanceof Closure;
var_dump($arrow());
function plain() { return Closure::getCurrent(); }
try { plain(); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
try { Closure::getCurrent(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
$fc = plain(...);
try { $fc(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
class K { function m() { return (function () { return get_class(Closure::getCurrent()); })(); } }
var_dump((new K)->m());
$fib = function ($n) { static $calls = 0; $calls++; return $n < 2 ? $n : Closure::getCurrent()($n - 1) + Closure::getCurrent()($n - 2); };
var_dump($fib(10));
class M { function m() { return (function () { return get_class(Closure::getCurrent()); })(); } }
var_dump((new M)->m());
class L { function m() { $f = function () { return get_class(Closure::getCurrent()); }; return $f(); } }
var_dump((new L)->m());
