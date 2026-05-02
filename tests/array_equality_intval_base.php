<?php

// loose array equality ignores key order
$a1 = ['x' => 1, 'y' => 2, 'z' => 3];
$a2 = ['z' => 3, 'x' => 1, 'y' => 2];
var_dump($a1 == $a2);
var_dump($a1 === $a2);

// strict equality requires same order
$a3 = ['x' => 1, 'y' => 2];
$a4 = ['x' => 1, 'y' => 2];
var_dump($a3 === $a4);

// nested arrays
$n1 = ['k' => ['a' => 1, 'b' => 2]];
$n2 = ['k' => ['b' => 2, 'a' => 1]];
var_dump($n1 == $n2);
var_dump($n1 === $n2);

// loose still false for different values
$d1 = ['x' => 1];
$d2 = ['x' => 2];
var_dump($d1 == $d2);

// mismatched length
var_dump(['a', 'b'] == ['a', 'b', 'c']);

// intval base 0 auto-detection
var_dump(intval('0x1A', 0));
var_dump(intval('012', 0));
var_dump(intval('0b101', 0));
var_dump(intval('42', 0));
var_dump(intval('-0x10', 0));
var_dump(intval('-012', 0));
var_dump(intval('0', 0));
