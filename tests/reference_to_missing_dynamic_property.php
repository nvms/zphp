<?php
// taking a reference to a missing property through a name in a variable
// creates it as null, as the written form does, with the deprecation for a
// class that doesn't allow dynamic properties

class Plain {}

set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});

$o = new stdClass;
$float = 0.0;
$r1 =& $o->$float;
$name = 'named';
$r2 =& $o->{$name};
$int = 7;
$r3 =& $o->$int;
var_dump($o);
$r2 = 'through the reference';
var_dump($o->named);

$p = new Plain;
$r4 =& $p->$name;
var_dump($p);
