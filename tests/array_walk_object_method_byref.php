<?php
// regression: array_walk with an object-method callable [$obj, 'm'] or a
// static-method callable [Class::class, 'm'] propagates by-ref param
// mutations back to the array entries. previously invokeCallableRef for
// non-string callables dropped the by-ref semantics, so the callback's
// `&$v = ...` had no effect when dispatched via object methods
class Cap {
    public function up(&$v, $k) { $v = strtoupper($v) . ":$k"; }
    public static function dbl(&$v, $k) { $v = "$v$v"; }
}
$arr = ['a', 'b', 'c'];
array_walk($arr, [new Cap(), 'up']);
print_r($arr);

$arr = ['x', 'y'];
array_walk($arr, [Cap::class, 'dbl']);
print_r($arr);

// __invoke object callable
class Inc {
    public function __invoke(&$v, $k) { $v++; }
}
$arr = [10, 20, 30];
array_walk($arr, new Inc());
print_r($arr);

// closure already works; verify it still does
$arr = [1, 2, 3];
array_walk($arr, function(&$v, $k) { $v *= 100; });
print_r($arr);
