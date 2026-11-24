<?php
// php 8.6: a reference into a WeakMap no longer needs the key there first
$obj = new stdClass;
$map = new WeakMap;
$int = 0;
$map[$obj] = &$int;
$int++;
var_dump($map[$obj], count($map));
$other = new stdClass;
$ref = &$map[$other];
var_dump($ref, count($map));
$ref = 'set';
var_dump($map[$other]);
$third = new stdClass;
$map[$third][] = 1;
$map[$third][] = 2;
var_dump(count($map));
unset($third);
var_dump(count($map));
try {
    var_dump($map[new stdClass]);
} catch (Error $e) {
    echo get_class($e), ': ', preg_replace('/#\d+/', '#N', $e->getMessage()), "\n";
}
var_dump(isset($map[new stdClass]), $map[new stdClass] ?? 'default');
// unserialize('') now warns, and C: data for a class without an unserializer fails
var_dump(@unserialize(''), error_get_last()['message']);
var_dump(@unserialize('C:8:"stdClass":0:{}'), error_get_last()['message']);
