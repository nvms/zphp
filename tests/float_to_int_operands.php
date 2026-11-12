<?php
// fractional floats used where php needs an int are deprecated, and floats
// past the int range warn
error_reporting(E_ALL);
$f = 6.5;
var_dump($f % 2, 7 % 2.5);
$x = 6.5;
$x %= 2;
var_dump($x);
$s = "6.5";
var_dump($s % 2, $s | 1, 1.5 & 3, 1.5 ^ 3, 1.5 << 2, 9.5 >> 1);
$arr = ['a', 'b', 'c'];
var_dump($arr[1.5]);
$arr[2.5] = 'd';
var_dump(isset($arr[1.7]), $arr);
$arr[1e42] = 'big';
var_dump(array_key_last($arr));
var_dump(1e42 | 0);
try {
    var_dump(5 % 0.5);
} catch (DivisionByZeroError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(eval('return [(integer) "5", (boolean) 1, (double) "2", (binary) 3];'));
