<?php
// destructuring into elements of a variable stores them as `$v[k] = x`
// does: string offsets write into the string
$str = 'ab';
list($str[0], $str[1]) = ['x', 'y'];
var_dump($str);
$s = 'hello';
[$s[0], $s[4]] = ['J', 'y'];
var_dump($s);
['a' => $t[1], 'b' => $t[0]] = ['a' => 'A', 'b' => 'B'];
var_dump($t);
$arr = [1, 2];
[$arr[0], $arr[1]] = [$arr[1], $arr[0]];
var_dump($arr);
function inner() {
    $local = 'zz';
    [$local[1]] = ['q'];
    return $local;
}
var_dump(inner());
foreach ([['m', 'n']] as [$w[0], $w[1]]) {}
var_dump($w);
