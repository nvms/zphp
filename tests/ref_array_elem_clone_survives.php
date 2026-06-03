<?php

// PHP preserves an element's is_ref status across an array COPY: if $c[$k] is a
// reference, then `$d = $c` makes $d[$k] the SAME storage, so writing either
// side (or the bound variable) is seen by all. zphp shares the ref cell across
// the clone and binds the clone's entry so the write propagates.

// copy then write the copy
$c = [10, 20];
$w = &$c[1];
$d = $c;
$d[1] = 77;
echo "copy-write-copy: c1={$c[1]} w=$w d1={$d[1]}\n";   // 77 77 77

// copy then write the original
$c2 = [1, 2];
$r2 = &$c2[0];
$e2 = $c2;
$c2[0] = 88;
echo "copy-write-orig: c0={$c2[0]} r=$r2 e0={$e2[0]}\n"; // 88 88 88

// copy then write through the bound variable
$c3 = [5, 6];
$r3 = &$c3[1];
$e3 = $c3;
$r3 = 99;
echo "copy-write-var: c1={$c3[1]} r=$r3 e1={$e3[1]}\n";  // 99 99 99

// is_ref survives into a by-value function parameter
function bump(array $x): void { $x[0] = 1000; }
$c4 = [1, 2];
$r4 = &$c4[0];
bump($c4);
echo "byval-param: c0={$c4[0]} r=$r4\n";                 // 1000 1000

// reference to an inner array, copied, then inner element written via copy
$cfg = ['db' => ['x' => 1]];
$ref = &$cfg['db'];
$copy = $cfg;
$copy['db']['x'] = 42;
echo "nested-copy: cfg={$cfg['db']['x']} ref={$ref['x']} copy={$copy['db']['x']}\n"; // 42 42 42

// a non-referenced element keeps value semantics across copy (no leakage)
$p = [1, 2];
$q = $p;
$q[0] = 9;
echo "plain-copy: p0={$p[0]} q0={$q[0]}\n";              // 1 9
