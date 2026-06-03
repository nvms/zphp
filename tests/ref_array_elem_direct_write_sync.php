<?php

// `$v = &$arr[$k]` makes $v and $arr[$k] one storage. writing the element
// DIRECTLY (not through $v) must be visible through $v - the array analog of
// prop_ref_direct_write_sync. zphp keeps the element slot and the ref cell as
// two views and syncs the cell on every direct element write

$a = [1, 2, 3];
$v = &$a[0];
$a[0] = 99;
echo "plain: v=$v a0={$a[0]}\n";        // 99 99

$a[0] += 1;
echo "compound: v=$v a0={$a[0]}\n";     // 100 100

// reverse direction still works (write through $v reaches the element)
$v = 5;
echo "reverse: v=$v a0={$a[0]}\n";      // 5 5

// string key
$m = ['k' => 'a'];
$rk = &$m['k'];
$m['k'] = 'z';
echo "strkey: rk=$rk mk={$m['k']}\n";   // z z

// depth-2: a reference to an inner array, write the inner element directly
$cfg = ['db' => ['x' => 1, 'y' => 2]];
$r = &$cfg['db'];
$cfg['db']['x'] = 50;
echo "nested: rx={$r['x']} cfgx={$cfg['db']['x']}\n";  // 50 50

// two independent refs into the same array don't cross-talk
$b = [10, 20];
$r0 = &$b[0];
$r1 = &$b[1];
$b[0] = 111;
$b[1] = 222;
echo "two refs: r0=$r0 r1=$r1\n";       // 111 222

// a non-referenced element writes normally (the guard path)
$c = [1, 2];
$c[1] = 8;
echo "unref: {$c[1]}\n";                // 8
