<?php
// null as an array offset names the "" key everywhere, constant
// expressions included. (php 8.5.5 and later also deprecate it, which
// php-src's tests/basic/array_null_offset_deprecation.phpt and
// Zend/tests/offsets/null_offset_*.phpt check)

function g($a = [null => 6, 'k' => [null => 7]]) {
    return $a;
}
var_dump(g());

const C = [null => 1];
class K {
    const D = [null => 2];
    public $p = [null => 3];
}
var_dump(C, K::D, (new K)->p);

$x = [null => 1];
$x[null] = 2;
$x[null] .= 'a';
var_dump($x, $x[null], isset($x[null]), $x[null] ?? 'none');
$y = [];
$y['a'][null] = 1;
$y[null]['b'] = 2;
[null => $q] = ['' => 3];
var_dump($y, $q);
for ($i = 0; $i < 3; $i++) {
    $z[null] = $i;
}
var_dump($z);
unset($z[null]);
var_dump($z);
