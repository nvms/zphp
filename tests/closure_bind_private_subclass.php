<?php
class P {
    private int $p = 1;
    protected int $q = 2;
}
class C extends P {
    private int $c = 3;
    public function readAll(): array { return [$this->p ?? null, $this->q, $this->c]; }
}

$obj = new C;
$reader = function() { return [$this->p ?? null, $this->q, $this->c]; };
$bound = Closure::bind($reader, $obj, C::class);
print_r($bound());

$inner = function() { return $this->p ?? "none"; };
$bound = Closure::bind($inner, $obj, C::class);
echo $bound(), "\n";

$boundP = Closure::bind($inner, $obj, P::class);
echo $boundP(), "\n";

class Box {
    private int $val = 42;
}
$set = function($v) { $this->val = $v; };
$get = function() { return $this->val; };
$box = new Box;
Closure::bind($set, $box, Box::class)(99);
echo Closure::bind($get, $box, Box::class)(), "\n";

$inc = (function() { return ++$this->val; })->bindTo($box, Box::class);
echo $inc(), " ", $inc(), " ", $inc(), "\n";

class Holder {
    private static int $sval = 100;
}
$sget = function() { return self::$sval; };
$bound = Closure::bind($sget, null, Holder::class);
echo $bound(), "\n";

$x = 10;
$inc = function() use (&$x) { $x++; };
$inc(); $inc(); $inc();
echo $x, "\n";

$arr = [];
$push = function($v) use (&$arr) { $arr[] = $v; };
$push("a"); $push("b"); $push("c");
print_r($arr);

$counter = 0;
$factory = function() use (&$counter) {
    return function() use (&$counter) { return ++$counter; };
};
$c1 = $factory();
$c2 = $factory();
echo $c1(), " ", $c1(), " ", $c2(), " ", $c1(), "\n";
echo $counter, "\n";

$fn = Closure::fromCallable("strtoupper");
echo $fn("hello"), "\n";

class WithMethod {
    public function double(int $x): int { return $x * 2; }
    public static function triple(int $x): int { return $x * 3; }
}
$obj = new WithMethod;
echo Closure::fromCallable([$obj, "double"])(21), "\n";
echo $obj->double(...)(11), "\n";
echo Closure::fromCallable("WithMethod::triple")(7), "\n";
echo Closure::fromCallable(["WithMethod", "triple"])(8), "\n";
