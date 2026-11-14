<?php
// a reference inside a sorted array still names the element after the sort
// moved it

$x = 1;
$refs = [3, &$x, 2];
sort($refs);
$x = 10;
var_dump($refs);

$y = 1;
$keyed = ['b' => 1, 'a' => &$y];
ksort($keyed);
$y = 4;
var_dump($keyed);

$z = 0;
$user = [5, &$z, 9];
usort($user, fn($a, $b) => $a <=> $b);
$z = 7;
var_dump($user);
