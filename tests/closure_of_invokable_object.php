<?php
// a closure made from an invokable object is a closure of its __invoke
// method, and a closure's own __invoke(...) is the closure itself

class Base {
    public function __invoke($a, $b = 2) {
        echo static::class, " ", get_class($this), " ", $a + $b, "\n";
    }
}
class Child extends Base {}

$obj = new Child;
$a = Closure::fromCallable($obj);
$b = Closure::fromCallable([$obj, '__invoke']);
$c = $obj(...);
var_dump($a);
var_dump($a == $b, $a == $c);
$a(1);
$c(1, 5);

// a closure of a method can't take another scope, so binding refuses
var_dump(@Closure::bind($a, new Child, stdClass::class));
$bound = Closure::bind($a, new Child);
$bound(10);

$fn = function ($x) { return $x * 2; };
var_dump($fn->__invoke(...) === $fn);
var_dump([$fn, '__invoke'](...) === $fn);
var_dump($fn->__INVOKE(...) === $fn);

$from = Closure::fromCallable($obj);
var_dump($from->__invoke(...) === $from);
$from->__invoke(...)(3);
