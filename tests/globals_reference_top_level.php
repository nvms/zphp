<?php
// a reference to $GLOBALS['x'] taken in the main script is the global
// variable itself

$x = 1;
$ref =& $GLOBALS['x'];
$ref++;
var_dump($x);
$x = 10;
var_dump($ref);

$ref2 =& $GLOBALS['fresh'];
$ref2 = 'made';
var_dump($fresh);

function f() {
    global $x;
    $x++;
    $r =& $GLOBALS['x'];
    $r++;
}
f();
var_dump($x, $ref);
unset($ref);
$x = 5;
var_dump($GLOBALS['x']);
