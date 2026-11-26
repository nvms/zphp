<?php
// a write fetch through a call that returns a reference to null or false
// makes the referenced variable an array (FETCH_DIM_W on the call's VAR)
function &foo() {
    global $foo;
    echo __FUNCTION__, "\n";
    return $foo;
}
function bar() {
    echo __FUNCTION__, "\n";
}
foo(bar())['bar'] ??= 42;
var_dump($foo);
$foo = null;
foo()['a']['b'] = 1;
var_dump($foo);
$foo = null;
foo()[] = 'x';
foo()['n'] .= 'y';
var_dump($foo);

class Box {
    public $items;
    public static $shared;
    public $flag = false;
    function &items() { return $this->items; }
    static function &shared() { return self::$shared; }
    function &flag() { return $this->flag; }
}
$b = new Box;
$b->items()['k'] = 'v';
$b->items()['k'] .= 'w';
Box::shared()[] = 1;
Box::shared()[] = 2;
var_dump($b->items, Box::$shared);
$b->flag()['x'] = 1;
var_dump($b->flag);

// a by-value result stays a temporary
function byval() { global $v; return $v; }
$v = null;
byval()['lost'] = 1;
var_dump($v);

// the same site with a by-reference and a by-value callee
$r = null;
function &refd() { global $r; return $r; }
function vald() { global $r; return $r; }
foreach (['refd', 'vald', 'refd'] as $i => $f) {
    $r = null;
    $f()[$i] = $i;
    var_dump($r);
}
