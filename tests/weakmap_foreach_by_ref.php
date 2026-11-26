<?php
// a by-reference foreach over a WeakMap binds its elements themselves
$map = new WeakMap;
$a = new stdClass;
$b = new stdClass;
$c = new stdClass;
$map[$a] = 1;
$map[$b] = [1, 2];
$map[$c] = 'x';
foreach ($map as $k => &$v) {
    if (is_int($v)) $v *= 10;
    elseif (is_array($v)) $v[] = 3;
    else $v .= 'y';
}
unset($v);
var_dump($map[$a], $map[$b], $map[$c]);
var_dump($map);

foreach ($map as $k => &$v) {
    $v = 'last';
}
var_dump($map);
var_dump($v);
$v = 'through';
var_dump($map[$c]);

try {
    foreach ($map->getIterator() as &$w) {}
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

$x = 5;
$map[$a] = &$x;
unset($x);
var_dump($map);
unset($a);
var_dump(count($map));
$m2 = clone $map;
var_dump($m2);
unset($map, $m2);
echo "done\n";
