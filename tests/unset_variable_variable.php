<?php
// unset($$name) unsets the variable the name names, also when the name is
// itself a reference
$name = 'var';
$$name = 42;
var_dump(isset($var));
unset($$name);
var_dump(isset($var));
$ref =& $name;
$$name = 42;
unset($$name);
var_dump(isset($var), $name);
function f() {
    $n = 'v';
    $v = new ArrayObject([1]);
    $w = $v;
    unset($$n);
    var_dump(isset($v), count($w));
    $i = 7;
    ${7} = 'seven';
    unset($$i);
    var_dump(isset(${7}));
}
f();
$GLOBALS['g'] = 1;
$gn = 'g';
unset($$gn);
var_dump(isset($g), array_key_exists('g', $GLOBALS));
class Foo { public static $bar = 42; }
foreach ([42, 1.5, true] as $n) {
    try { var_dump(Foo::${$n}); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
$c = 'Foo';
try { var_dump($c::${42}); } catch (Error $e) { echo $e->getMessage(), "\n"; }
