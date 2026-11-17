<?php
// an assignment through an array element bound to a typed property's
// reference evaluates to the value the property took

class Test {
    public ?string $prop;
    public int $num = 0;
    public array $arr = [];
    public static array $sarr = [];
}

function local() {
    $obj = new Test;
    $ary = [];
    $ary[0] =& $obj->prop;
    var_dump($ary[0] = 0);
    var_dump($obj->prop);
    $ary['n'] =& $obj->num;
    var_dump($ary['n'] = "42");
    var_dump($ary['n'] = 1.0);
}
local();

$obj = new Test;
$g = [];
$g[1] =& $obj->prop;
var_dump($g[1] = 5);

$nested = ['in' => []];
$nested['in'][0] =& $obj->num;
var_dump($nested['in'][0] = "7");

$obj->arr[0] =& $obj->prop;
var_dump($obj->arr[0] = 3.5);

Test::$sarr[0] =& $obj->num;
var_dump(Test::$sarr[0] = "9");
var_dump($obj);
