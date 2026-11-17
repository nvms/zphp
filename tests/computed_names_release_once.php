<?php
// names and values computed for one operation (a temporary string or array)
// are let go once, after the operation used them
class Foo {
    public const BAR = 'bar';
    public $a = 1;
}
$ba = "BA";
$r = "R";
var_dump(Foo::{$ba . $r}, Foo::{strtoupper("bar")});
$cls = "Fo" . "o";
var_dump($cls::{$ba . $r}, (strtolower("FOO"))::BAR);
$xy = 1;
$x = "x";
unset(${$x . "y"});
var_dump(isset($xy));
$GLOBALS['zz'] = 2;
function g() {
    $n = "z";
    unset($GLOBALS[$n . "z"]);
}
g();
var_dump(isset($zz));
$o = new Foo;
$c = clone($o, ['a' => str_repeat("q", 3)]);
var_dump($c->a, clone($o, array_merge(['a' => 5])));
