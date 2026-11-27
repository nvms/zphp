<?php
// an append's containers are fetched after its right side runs: an
// assignment there that writes the variable, or binds a reference to it,
// is seen by the write
function a() {
    $a[] = $b[] = &$a;
    var_dump($a, $b);
}
function b() {
    $a[] = $b = &$a;
    var_dump($a, $b);
}
function c() {
    $a = [1];
    $a[] = $a = [5];
    var_dump($a);
}
function d() {
    $a[0][] = $b[] = &$a;
    var_dump($a, $b);
}
function e() {
    $a = ['x'];
    $a[] = $c = $a[] = 'y';
    var_dump($a, $c);
}
a();
b();
c();
d();
e();

// the same at the top level
$g[] = $h[] = &$g;
var_dump($g, $h);
$i = [1];
$i[] = $i = [7];
var_dump($i);
