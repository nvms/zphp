<?php
// a by-reference foreach over a variable that holds no array warns and
// leaves the variable as it was: an undefined one stays undefined, null and
// false are not made arrays, and an int is no error

foreach ($undefined as &$v) {
    $v = 1;
}
var_dump(isset($undefined));
var_dump($undefined);

foreach ([null, false, 5, 1.5, 'text', true] as $value) {
    $u = $value;
    foreach ($u as $k => &$v) {
        $v = 9;
    }
    var_dump($u);
}

function inside() {
    foreach ($w as &$v) {
    }
    var_dump(isset($w));
    $n = null;
    foreach ($n as &$v) {
    }
    var_dump($n);
    $a = [1, 2];
    $copy = $a;
    foreach ($a as &$v) {
        $v *= 10;
    }
    unset($v);
    var_dump($a, $copy);
}
inside();

$o = new stdClass;
$o->p = 1;
$u = $o;
foreach ($u as &$v) {
    $v = 'changed';
}
var_dump($o);
