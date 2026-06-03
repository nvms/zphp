<?php

// `$arr[$k] = &$var` and `$arr[] = &$var` bind the element to $var's storage:
// they become one reference, so writing either side is seen by the other. this
// is the assign direction (the read direction is `$v = &$arr[$k]`).

// keyed bind, write through the variable
$a = [1, 2];
$x = 9;
$a[0] = &$x;
$x = 5;
echo "keyed: a0={$a[0]}\n";        // 5

// write through the element reaches the variable
$a[0] = 7;
echo "keyed-rev: x=$x\n";          // 7

// push form
$b = [];
$y = 1;
$b[] = &$y;
$y = 42;
echo "push: b0={$b[0]}\n";         // 42
$b[0] = 100;
echo "push-rev: y=$y\n";           // 100

// string key
$m = [];
$s = 'a';
$m['k'] = &$s;
$s = 'z';
echo "strkey: mk={$m['k']}\n";     // z

// bind then copy the array: the reference survives the copy (bug-1 + bug-2)
$c = [1, 2];
$z = 10;
$c[1] = &$z;
$d = $c;
$z = 99;
echo "bind+copy: c1={$c[1]} d1={$d[1]} z=$z\n";  // 99 99 99

// two elements bound to two distinct variables, no cross-talk
$arr = [0, 0];
$p = 5;
$q = 6;
$arr[0] = &$p;
$arr[1] = &$q;
$p = 50;
$q = 60;
echo "two: {$arr[0]} {$arr[1]}\n"; // 50 60

// binding to an already-referenced variable shares one cell
$e = [0];
$base = 1;
$alias = &$base;
$e[0] = &$base;
$alias = 7;
echo "shared-cell: e0={$e[0]} base=$base alias=$alias\n";  // 7 7 7
