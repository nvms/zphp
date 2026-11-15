<?php
// a WeakMap hands out its element for writes (zend_weakmap_read_dimension):
// nested writes, increments and references reach the stored value
$a = new stdClass;
$b = new stdClass;
$map = new WeakMap;
$map[$a] = [];
$map[$a][] = 42;
$map[$a]['k'] = 'v';
$map[$b] = 41;
$map[$b]++;
$map[$b] += 10;
var_dump($map[$a], $map[$b]);

$n = 1;
$map[$a] = 0;
$map[$a] = &$n;
$n++;
var_dump($map[$a], $map->offsetGet($a));

$ref = &$map[$b];
$ref = 'through a reference';
var_dump($map[$b]);

try {
    $map[new stdClass][] = 1;
} catch (Error $e) {
    echo get_class($e), ": ", preg_replace('/#\d+/', '#N', $e->getMessage()), "\n";
}
try {
    $map['x']++;
} catch (TypeError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump(count($map));
