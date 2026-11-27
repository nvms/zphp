<?php
// ArrayObject::__serialize() hands out the storage itself: a listing of the
// result sees the one table (an object inside it shows *RECURSION*), and a
// write on either side afterwards separates it

$o = new ArrayObject();
$y = new stdClass();
$o->append($y);
$o->append($o);
$state = $o->__serialize();
var_dump($state);

$state[1][] = 'added to the copy';
$o['k'] = 'added to the object';
var_dump(count($state[1]), count($o));

$v = 1;
$r = new ArrayObject(['a' => 1]);
$r['b'] = &$v;
$s = $r->__serialize();
$v = 2;
var_dump($s[1], $r->getArrayCopy());
$s[1]['b'] = 3;
var_dump($v, $r['b']);
echo serialize($r), "\n";
