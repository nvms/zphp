<?php
// circular self-reference
$a = new stdClass;
$a->self = $a;
print_r($a);

// mutual recursion
$b = new stdClass; $c = new stdClass;
$b->c = $c;
$c->b = $b;
print_r($b);

// circular array (via ref)
$arr = [1, 2];
$arr[] = &$arr;
print_r($arr);

// non-circular still works fine
$deep = ['a' => ['b' => ['c' => 'leaf']]];
print_r($deep);

// print_r with return=true on circular
$x = new stdClass;
$x->self = $x;
$s = print_r($x, true);
echo strpos($s, '*RECURSION*') !== false ? "ok\n" : "missing\n";

// repeated calls reset state
$y = new stdClass;
$y->n = 1;
print_r($y);
print_r($y);

// shared (non-circular) refs - second should NOT show recursion
$shared = new stdClass; $shared->v = 'sh';
$wrap = ['a' => $shared, 'b' => $shared];
print_r($wrap);
