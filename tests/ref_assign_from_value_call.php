<?php
// `$x =& f()` where f returns by value: php's notice, then an ordinary
// assignment; the value must stay alive for every other holder

class Foo
{
    public $n = 0;
    function getThis() { return $this; }
    function destroyThis()
    {
        $baz =& $this->getThis();
        $baz->n++;
        return $baz;
    }
}

function make() { return new Foo; }
function id($v) { return $v; }
function arr() { return [1, 2, 3]; }

$bar = new Foo();
$bar->destroyThis();
var_dump($bar);

function inner()
{
    $o = new Foo;
    $x =& id($o);
    $x->n = 5;
    $y = $o;
    return [$x === $o, $y->n];
}
var_dump(inner());

$y =& make();
var_dump($y);
$y->n = 7;
var_dump($y);

$a =& arr();
$a[] = 4;
var_dump($a);

var_dump($z =& id("str"));
var_dump($z);

for ($i = 0; $i < 3; $i++) {
    $w =& make();
    $w->n = $i;
}
var_dump($w);
