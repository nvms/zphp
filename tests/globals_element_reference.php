<?php
// $GLOBALS['x'] taken by reference is the global variable x itself: returned
// by reference, assigned by reference, or iterated by reference
function &globalRef() {
    return $GLOBALS['a'];
}

function &dynamicRef($name) {
    return $GLOBALS[$name];
}

$a = 4;
$b = &globalRef();
$a++;
var_dump($a, $b);
$b = 10;
var_dump($a);

$c = &dynamicRef('fresh');
$c = 'made';
var_dump($fresh);

function bump() {
    $local = &$GLOBALS['counter'];
    $local++;
    $a = 'local a';
    $r = &$GLOBALS['a'];
    $r = 'from bump';
    var_dump($a);
}
$counter = 1;
bump();
bump();
var_dump($counter, $a, $b);

// a by-reference function returning another one's non-variable result
function &constantByRef() {
    return 100;
}
function &passOn() {
    return constantByRef();
}
$d = &passOn();
var_dump($d);
