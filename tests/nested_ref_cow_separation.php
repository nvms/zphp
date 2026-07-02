<?php
// case 1: ref to inner array, outer COW-shared via assignment, write through outer
$x = ['k' => [1, 2]];
$y = &$x['k'];
$b = $x;
$x['k'][] = 9;
echo "c1: ", count($y), " ", count($b['k']), "\n";

// case 2: ref to inner array, outer passed by value to a function, write after
function noop($x) {}
$x2 = ['k' => [1, 2]];
$y2 = &$x2['k'];
noop($x2);
$x2['k'][] = 9;
echo "c2: ", count($y2), "\n";

// case 3: write through the reference after outer is shared
$x3 = ['k' => [1, 2]];
$y3 = &$x3['k'];
$b3 = $x3;
$y3[] = 9;
echo "c3: ", count($x3['k']), " ", count($b3['k']), "\n";

// case 4: object property array referenced, object prop written via chain
class Box { public $p = ['a' => [1, 2]]; }
$o = new Box();
$r = &$o->p['a'];
$copy = $o->p;
$o->p['a'][] = 9;
echo "c4: ", count($r), " ", count($copy['a']), "\n";

// case 5: nested vivify through a referenced inner
$x5 = ['k' => [1, 2]];
$y5 = &$x5['k'];
noop($x5);
$x5['k']['sub'] = 1;
echo "c5: ", count($y5), "\n";

// case 6: local var referenced then ensure_array path (append to referenced local)
$a6 = [1, 2];
$r6 = &$a6;
$b6 = $a6;
$a6[] = 3;
echo "c6: ", count($r6), " ", count($b6), "\n";
