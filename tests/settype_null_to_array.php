<?php
// regression: settype($x, 'array') on a null value produces an empty array,
// matching PHP's (array) cast. previously zphp wrapped null into a
// one-element array [null]. non-null scalars still wrap into [value].
$a = null;
settype($a, 'array');
var_dump($a);                 // array(0) {}

$b = 5;
settype($b, 'array');
var_dump($b);                 // array(1) { [0] => int(5) }

$c = 'text';
settype($c, 'array');
var_dump($c);                 // array(1) { [0] => string }

$d = true;
settype($d, 'array');
var_dump($d);                 // array(1) { [0] => bool(true) }

$e = [1, 2];
settype($e, 'array');
var_dump($e);                 // unchanged

// the (array) cast and settype agree
var_dump((array)null === []);
var_dump((array)5 === [5]);

// settype return value is true
$f = null;
var_dump(settype($f, 'array'));

// object -> array via settype keeps properties
$o = (object)['x' => 1, 'y' => 2];
settype($o, 'array');
var_dump($o);
