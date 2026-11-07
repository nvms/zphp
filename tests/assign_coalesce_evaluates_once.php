<?php
// a ??= target evaluates each call on its path once, reads through php's
// quiet fetch, and writes only when the value is null

class Foo {
    public $prop;
    public function foo() { echo __METHOD__, "\n"; return $this; }
    public function bar() { echo __METHOD__, "\n"; return 'prop'; }
}

function k($x) { echo "k($x)\n"; return $x; }

$foo = new Foo();
$foo->foo()->foo()->{$foo->bar()} ??= 42;
var_dump($foo);
$foo->foo()->{$foo->bar()} ??= 43;
var_dump($foo->prop);

$o = new stdClass;
$n = 'dyn';
$o->$n ??= 1;
$o->$n ??= 2;
$o->{'x' . 'y'} ??= 3;
var_dump($o);
var_dump($o->{k('dyn')} ??= 9);
var_dump($o->{k('new')} ??= 10);

$a = ['x' => ['y' => 1]];
$a[k('x')]['y'] ??= 2;
$a[k('x')]['z'] ??= 3;
$a[k('n')]['z'] ??= 4;
var_dump($a);
$b = null;
$b[k('p')][k('q')] ??= 5;
var_dump($b);
$ao = new ArrayObject(['m' => null]);
$ao[k('m')] ??= 6;
var_dump($ao['m']);
$s = ['s' => 'str'];
var_dump($s[k('s')] ??= 'other');

$arr = [[1]];
$r = &$arr[0];
$copy = $arr;
$arr[k(0)][k(5)] ??= 9;
var_dump($copy, $arr);

function make() { echo "make\n"; return ['a' => null, 'b' => 1]; }
var_dump(make()['a'] ??= 'filled');
var_dump(make()['b'] ??= 'filled');
