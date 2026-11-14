<?php
// usort, uasort and uksort sort a copy: the callback sees the variable as it
// was, and what it does to the variable is replaced by the sorted result

function cmp($a, $b) {
    unset($GLOBALS['list'][2]);
    return $a <=> $b;
}
$list = [1 => 'c', 2 => 'a', 3 => 'b'];
usort($list, 'cmp');
var_dump($list);

$seen = [];
$data = ['b' => 2, 'a' => 1, 'c' => 3];
uasort($data, function ($x, $y) use (&$seen, &$data) {
    $seen[] = count($data);
    return $x <=> $y;
});
var_dump($data, array_unique($seen));

$keys = ['z' => 1, 'y' => 2];
uksort($keys, function ($a, $b) use (&$keys) {
    $keys['added'] = true;
    return strcmp($a, $b);
});
var_dump($keys);
