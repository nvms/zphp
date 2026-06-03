<?php

// unset($arr[$k]) on a referenced element breaks the reference: a later write
// through the (still-live) bound variable must NOT resurrect the element. and a
// reference bound inside a function survives the function's frame teardown.

// assign-direction unset ($arr[k] = &$var)
$a = [1, 2, 3];
$x = 9;
$a[1] = &$x;
unset($a[1]);
$x = 100;
echo "assign-unset: x=$x has1=", (isset($a[1]) ? 'y' : 'n'), " a=", implode(',', $a), "\n"; // 100 n 1,3

// read-direction unset ($v = &$arr[k])
$b = [10, 20, 30];
$v = &$b[1];
unset($b[1]);
$v = 200;
echo "read-unset: v=$v has1=", (isset($b[1]) ? 'y' : 'n'), " b=", implode(',', $b), "\n";   // 200 n 10,30

// a reference bound inside a function survives frame teardown
function make(): array {
    $arr = [0, 0];
    $local = 7;
    $arr[0] = &$local;
    $local = 70;
    return $arr;
}
$r = make();
echo "func-return: r0={$r[0]} r1={$r[1]}\n";  // 70 0
$r[0] = 1;
echo "func-after: r0={$r[0]}\n";              // 1

// unset one of two refs leaves the other intact
$c = [0, 0];
$p = 5;
$q = 6;
$c[0] = &$p;
$c[1] = &$q;
unset($c[0]);
$p = 50;
$q = 60;
echo "unset-one: has0=", (isset($c[0]) ? 'y' : 'n'), " c1={$c[1]} q=$q\n";  // n 60 60

// rebind after unset: bind a fresh ref to the same key
$d = ['k' => 1];
$m = 100;
$d['k'] = &$m;
unset($d['k']);
$n = 999;
$d['k'] = &$n;
$n = 7;
echo "rebind: dk={$d['k']} m=$m\n";  // 7 100
