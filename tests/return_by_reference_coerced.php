<?php
// a by-reference return coerced to the declared type coerces the
// referenced variable too
function test1(&$abc) : string {
    return $abc;
}

function &test2(int $abc) : string {
    return $abc;
}

function &test3(int &$abc) : string {
    return $abc;
}

$a = 123;

var_dump(test1($a));
var_dump($a);
var_dump(test2($a));
var_dump($a);
var_dump(test3($a));
var_dump($a);

class Box { public $v = 5; public function &get(): string { return $this->v; } }
$b = new Box;
var_dump($b->get(), $b->v);
function &floaty(array &$arr): float { return $arr[0]; }
$arr = [7];
var_dump(floaty($arr), $arr);
