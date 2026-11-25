<?php
// php 8.6's new gives a temporary, as a call does, so a commutative operator
// keeps a fetched constant or a call result on its left of a new
function f() { return STDOUT; }
foreach ([
    fn() => STDOUT * new stdClass,
    fn() => STDOUT & new stdClass,
    fn() => f() + new stdClass,
    fn() => new stdClass | STDOUT,
    fn() => new stdClass ^ f(),
    fn() => [] * new ArrayObject,
] as $g) {
    try {
        $g();
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
