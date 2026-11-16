<?php
// `$a[k] ??= v` evaluates v before the write fetch of $a, and `C::$$n ??= v`
// works on a dynamically named static property
$a[0] ??= $a;
var_dump($a);
$b = ['x' => null];
$b['x'] ??= count($b);
var_dump($b);

class Test {
    public static $foo;
    public static $bar = 'set';
}
$foo = 'foo';
$bar = 'bar';
Test::$$foo ??= 123;
Test::$$foo ??= 456;
Test::$$bar ??= 'unused';
var_dump(Test::$foo, Test::$bar);
function id($x) { echo "id($x)\n"; return $x; }
Test::$foo = null;
Test::${id($foo)} ??= 'computed';
var_dump(Test::${id($foo)} ??= 'again');
var_dump(Test::$foo);
$cls = 'Test';
$cls::$$foo = null;
$cls::$$foo ??= 'via variable class';
var_dump(Test::$foo);
