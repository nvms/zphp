<?php
class Box {
    public $v = 3;
    function make() {
        $k = 2;
        $f = function ($x) use ($k) { return $x * $k + $this->v; };
        $k = 100;
        return $f(5);
    }
}
function captures() {
    $a = 1;
    $f = function () use ($a) { return $a; };
    $a = 2;
    $g = fn() => $a * 10;
    $a = 3;
    echo $f(), " ", $g(), " ", $a, "\n";
    $list = [];
    for ($i = 0; $i < 3; $i++) $list[] = function () use ($i) { return $i; };
    echo implode(",", array_map(fn($c) => $c(), $list)), "\n";
    $h = function () use ($undefined) { return $undefined; };
    var_dump($h());
    $m = function () use ($a) { $a = 99; return $a; };
    echo $m(), " ", $a, "\n";
    $outer = 5;
    $nest = function () use ($outer) { return fn($y) => $outer + $y; };
    echo $nest()(1), "\n";
    $s = static fn() => $outer;
    echo $s(), "\n";
    $arr = [1, 2];
    $c = function () use ($arr) { $arr[] = 3; return count($arr); };
    echo $c(), " ", count($arr), "\n";
    $obj = new stdClass; $obj->n = 1;
    $o = function () use ($obj) { $obj->n++; };
    $o(); echo $obj->n, "\n";
    var_dump(array_keys(get_defined_vars()));
    echo implode(",", array_keys(compact('a', 'outer'))), "\n";
    return func_get_args();
}
var_dump(captures(7, 8));
echo (new Box)->make(), "\n";
function counter() {
    $n = 0;
    $inc = function () use (&$n) { $n++; };
    $inc(); $inc();
    $byval = function () use ($n) { return $n; };
    $n += 5;
    return [$n, $byval()];
}
var_dump(counter());
