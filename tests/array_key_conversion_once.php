<?php
// a compound assignment or increment on an element converts the key once,
// with one warning, as php does
set_error_handler(function ($no, $msg) { echo "  ", $msg, "\n"; });
$a = [];
$k = 1.5;
echo "assign\n";
$a[$k] = 1;
echo "add assign\n";
$a[$k] += 1;
echo "inc\n";
$a[$k]++;
echo "concat assign literal\n";
$a[2.5] .= 'x';
$r = fopen('php://memory', 'r');
echo "resource add assign\n";
$a[$r] = 1;
$a[$r] += 1;
$a[$r]--;
echo "null key\n";
$a[null] = 1;
$a[null] *= 5;
$a[true] = 1;
$a[true] -= 3;
$o = new ArrayObject();
$o[$k] = 1;
$o[$k] += 1;
var_dump($a, $o->getArrayCopy());
