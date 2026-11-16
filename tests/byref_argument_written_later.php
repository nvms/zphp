<?php
// a by-reference argument is a reference from the moment it is sent, so a
// later argument that writes the same variable writes through it

function show_ref(&$a, $b) {
    echo "a=", json_encode($a), " b=", json_encode($b), "\n";
    $a = is_array($a) ? count($a) : "set";
}

function second_ref($a, &$b, $c) {
    echo "a=", json_encode($a), " b=", json_encode($b), " c=", json_encode($c), "\n";
    $b = "written";
}

$x = 0;
show_ref($x, $x = 5);
var_dump($x);

$x = 1;
show_ref($x, $x++);
var_dump($x);

$x = 0;
second_ref($x, $x, $x = 1);
var_dump($x);

// the variable is already a reference
$x = 0;
$alias = &$x;
show_ref($x, $x = 9);
var_dump($x, $alias);
unset($alias);

// arrays, separated from a copy taken before the call
$arr = [1];
$copy = $arr;
show_ref($arr, $arr[] = 2);
var_dump($arr, $copy);

// an undefined variable is defined as null when sent
show_ref($undef, $undef = "late");
var_dump($undef);

// inside a function
function inner() {
    $v = "start";
    show_ref($v, $v = "changed");
    var_dump($v);
    $w = [1, 2];
    second_ref(0, $w, $w = [3]);
    var_dump($w);
}
inner();

// methods and static methods
class K {
    function m(&$a, $b) { echo "m a=", json_encode($a), "\n"; $a = "m"; }
    static function s(&$a, $b) { echo "s a=", json_encode($a), "\n"; $a = "s"; }
}
$x = 1;
(new K)->m($x, $x = 2);
var_dump($x);
K::s($x, $x = 3);
var_dump($x);

// a closure
$f = function (&$a, $b) { echo "closure a=", json_encode($a), "\n"; $a++; };
$x = 10;
$f($x, $x = 20);
var_dump($x);

// a typed by-reference parameter coerces the variable it binds
function to_int(int &$x) {}
function to_string(string &$x) {}
$x = 1.0;
to_int($x);
var_dump($x);
to_string($x);
var_dump($x);
