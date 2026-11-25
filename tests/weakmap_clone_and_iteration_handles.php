<?php
// a cloned WeakMap holds its keys weakly too and forgets a key that dies;
// iterating a WeakMap creates no object, so object handles stay as php's

$obj = new stdClass;
$ref = WeakReference::create($obj);
$map = new WeakMap;
$map[$obj] = 1;
$copy = clone $map;
var_dump(count($copy), $copy[$obj]);
$copy[$obj] = 2;
var_dump($map[$obj], $copy[$obj]);
unset($obj);
var_dump($ref->get(), count($map), count($copy));

$obj = new stdClass;
$ref = WeakReference::create($obj);
$map = new WeakMap;
$map[$obj] = 1;
$copy = clone $map;
unset($copy, $map, $obj);
var_dump($ref->get());

$map = new WeakMap;
foreach ($map as $k => $v) {}
$a = new stdClass;
$b = new stdClass;
$map[$a] = 'a';
$map[$b] = 'b';
foreach ($map as $k => $v) {
    var_dump(spl_object_id($k) - spl_object_id($a), $v);
    $inner = new stdClass;
    var_dump(spl_object_id($inner) - spl_object_id($b));
}
var_dump($map->getIterator() instanceof Iterator);
