<?php
[$a, [$b, $c]] = [1, [2, 3]];
list($d, list($e, $f)) = [4, [5, 6]];
['x' => [$g]] = ['x' => [7]];
list('y' => list($h)) = ['y' => [8]];
foreach ([[1, [2]]] as list($i, list($j))) {}
foreach ([[1, [2]]] as $k => [$l, [$m]]) {}
var_dump($a, $b, $c, $d, $e, $f, $g, $h, $i, $j, $l, $m);
$x = list($p) = [9];
var_dump($x, $p);
var_dump(list($q, $r) = [10, 11]);
$y = [list($s) = [12], 13];
var_dump($y, $s);
