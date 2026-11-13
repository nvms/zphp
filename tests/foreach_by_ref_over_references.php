<?php
// a by-reference foreach over elements that already are references binds
// the loop variable to those references

$a = 'a';
$b = 'b';
foreach ([&$a, &$b] as &$value) {
    $value .= '-foo';
}
unset($value);
var_dump($a, $b);

$c = 1;
$d = 2;
$list = [&$c, &$d, 3];
foreach ($list as $k => &$item) {
    $item *= 10;
    $item .= "!";
}
unset($item);
var_dump($c, $d, $list);

$x = 'x';
$outer = [&$x];
foreach ($outer as &$first) {
    foreach ($outer as &$second) {
        $second .= '2';
    }
    $first .= '1';
}
unset($first, $second);
var_dump($x);
