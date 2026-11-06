<?php
// a nested write through an ArrayObject fetches the inner element without
// warning about a missing key
error_reporting(E_ALL);
$test = new ArrayObject();
$test['d1']['d2'] = 'hello';
$test['d1']['d3'] = 'world';
$test['l'] = ['x'];
$test['l'][] = 'y';
print_r($test->getArrayCopy());
$o = new stdClass;
$w = new ArrayObject($o);
$w['a']['b'] = 1;
$w['a']['c'] = 2;
print_r($o);
var_dump($test['missing']);
