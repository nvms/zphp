<?php
// regression: list destructuring into array-element targets ($a[0], $a['k'],
// $a[]) was a no-op - the compiler only handled plain-variable and
// object-property slot targets, so [$a[0], $a[1]] = [...] dropped the writes.

// in-place swap idiom
$swap = [1, 2];
[$swap[0], $swap[1]] = [$swap[1], $swap[0]];
print_r($swap);

// integer-key targets, sparse
$b = [0, 0, 0];
[$b[0], $b[2]] = ['x', 'z'];
print_r($b);

// string-key targets
$c = [];
[$c['k1'], $c['k2']] = ['v1', 'v2'];
print_r($c);

// keyed list() syntax with array targets
$r = [];
['first' => $r[0], 'second' => $r[1]] = ['first' => 'A', 'second' => 'B'];
print_r($r);

// list() keyword form
$z = [];
list($z[0], $z[1]) = [100, 200];
print_r($z);

// append targets
$out = [];
[$out[], $out[]] = [1, 2];
print_r($out);

// append targets driven by foreach
$acc = [];
foreach ([[10, 20], [30, 40]] as [$acc[], $acc[]]);
print_r($acc);

// depth-2 array targets
$grid = [[0, 0], [0, 0]];
[$grid[0][0], $grid[1][1]] = [9, 8];
print_r($grid);

// mixed slot kinds in one destructure
$arr = [];
$obj = new stdClass;
[$plain, $arr['k'], $obj->p] = ['P', 'A', 'O'];
echo $plain, " ", $arr['k'], " ", $obj->p, "\n";

// nested list with array-element leaves
$m = [];
[[$m[0], $m[1]], [$m[2], $m[3]]] = [[1, 2], [3, 4]];
print_r($m);
