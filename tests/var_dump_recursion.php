<?php
// circular self-reference
$a = new stdClass;
$a->self = $a;
ob_start();
var_dump($a);
$out = ob_get_clean();
echo strpos($out, '*RECURSION*') !== false ? "rec1 ok\n" : "rec1 missing\n";

// circular pair
$b = new stdClass; $c = new stdClass;
$b->c = $c;
$c->b = $b;
ob_start();
var_dump($b);
$out = ob_get_clean();
echo strpos($out, '*RECURSION*') !== false ? "rec2 ok\n" : "rec2 missing\n";

// deep nesting that's not circular still works
$deep = ['a' => ['b' => ['c' => ['d' => 'leaf']]]];
ob_start();
var_dump($deep);
$out = ob_get_clean();
echo strpos($out, 'leaf') !== false ? "deep ok\n" : "deep missing\n";
echo strpos($out, '*RECURSION*') === false ? "no false rec\n" : "false rec\n";

// multiple var_dump calls reset visited
$x = new stdClass;
$x->n = 'first';
ob_start();
var_dump($x);
var_dump($x);
$out = ob_get_clean();
$count = substr_count($out, 'first');
echo "first appears $count times\n";

// non-circular object containing array
$o = new stdClass;
$o->arr = [1, 2, 3];
ob_start();
var_dump($o);
$out = ob_get_clean();
echo strpos($out, 'int(2)') !== false ? "arr ok\n" : "arr missing\n";

// array with object inside (no cycle)
ob_start();
var_dump([$x, $x]);
$out = ob_get_clean();
echo "shared obj count: ", substr_count($out, "first"), "\n";
