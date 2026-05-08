<?php
// PHP 8.3+: auto-key after negative starts at neg+1, not 0
$a = [];
$a[-3] = 'a';
$a[] = 'b';
$a[] = 'c';
print_r($a);

// after positive int, auto-key continues from there
$b = [];
$b[5] = 'x';
$b[] = 'y';
print_r($b);

// mix: highest int key wins
$c = [];
$c[-5] = 'a';
$c[10] = 'b';
$c[] = 'z';
print_r($c);

// only string keys: auto-key starts at 0
$d = [];
$d['x'] = 1;
$d[] = 'auto';
print_r($d);

// negative then larger negative
$e = [];
$e[-2] = 'a';
$e[-10] = 'b';
$e[] = 'c';
print_r($e);
