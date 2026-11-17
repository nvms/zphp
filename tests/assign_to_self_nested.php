<?php
// `$a[i][j] = $a` copies the right side before the containers are fetched
// for writing (zend_is_assign_to_self), so the array never holds itself
$a = array(array());
$b =& $a;
$a[0][0] = $a;
print_r($a); echo "\n";
$a = array(array());
$a[0][0] = $a;
print_r($a); echo "\n";
function f() {
    $a = array(array());
    $b =& $a;
    $a[0][0] = $a;
    print_r($a); echo "\n";
}
f();
$a = [[[]]];
$a[0][0][0] = $a;
print_r($a);
$a = [[]];
$a[0][] = $a;
print_r($a);
$a = [];
$a[] = $a;
print_r($a);
function g() {
    $a = [[[]]];
    $a[0][0][0] = $a;
    print_r($a);
    $a = [[]];
    $a[0][] = $a;
    print_r($a);
}
g();
$o = new stdClass;
$o->p = [[]];
$q = $o->p;
$o->p[0][0] = $q;
print_r($o);
