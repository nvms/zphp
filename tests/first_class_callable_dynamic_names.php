<?php

class A {
    public static function b($x) {
        return $x;
    }

    public function c($x) {
        return $x;
    }
}

$name = 'strlen';
$fn = $name(...);
var_dump($fn('x'));

$name = ['A', 'b'];
$fn = $name(...);
var_dump($fn(2));

$name = [new A, 'c'];
$fn = $name(...);
var_dump($fn(3));

$name1 = 'A';
$name2 = 'b';
$fn = $name1::$name2(...);
var_dump($fn(4));
$fn = A::$name2(...);
var_dump($fn(4.5));

$name2 = 'c';
$fn = (new A)->$name2(...);
var_dump($fn(5));
$fn = (new A)->{'c'}(...);
var_dump($fn(5.5));

$fn = [A::class, 'b'](...);
var_dump($fn(6));

$o = new stdClass;
$o->prop = A::b(...);
var_dump(($o->prop)(7));

// __call and __callStatic trampolines
class Foo {
    public function __call($method, $args) {
        return $method;
    }

    public static function __callStatic($method, $args) {
        return static::class . "::" . $method;
    }
}

class Bar extends Foo {}

$foo = new Foo;
$bar = $foo->anythingInstance(...);
echo $bar(), "\n";

$qux = Foo::anythingStatic(...);
echo $qux(), "\n";

$qux2 = Bar::anythingStatic(...);
echo $qux2(), "\n";

$n = "dyn";
$f = $foo->$n(...);
echo $f(), "\n";
$f = $foo->{"x" . $n}(...);
echo $f(), "\n";

// the name __call returns outlives the closure
$q = $foo->{"an" . "y"}(...);
$x = $q();
$y = [$x];
unset($q);
gc_collect_cycles();
echo $x, $y[0], "\n";
$r = Closure::fromCallable([$foo, "zz" . str_repeat("q", 2)]);
$x2 = $r();
unset($r);
echo $x2, "\n";
var_dump(array_map(fn($f) => $f(), [Closure::fromCallable([$foo, "bb" . str_repeat("q", 2)])]));
