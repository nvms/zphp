<?php
// taking a reference to an element that doesn't exist creates it as null

$a = [5];
$r = &$a['x'];
var_dump($a);
$r = 1;
var_dump($a);

$b = [5];
$r2 = &$b['1'];
$r2 = 3;
var_dump($b);

function inFunction() {
    $c = ['k' => 1];
    $ref = &$c['missing'];
    $ref = 'set';
    var_dump($c);
    $ref2 = &$c[7];
    $ref2 = 'seven';
    var_dump($c);
}
inFunction();

$n = [];
$deep = &$n['a']['b'];
$deep = 'deep';
var_dump($n);
