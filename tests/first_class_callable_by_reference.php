<?php
// a closure made from a function's name passes arguments to its
// by-reference parameters by reference, and returns its reference

function &id(&$x) { return $x; }
function inc(&$x) { $x++; }

$fn = id(...);
$i = 0;
$i2 =& $fn($i);
$i++;
var_dump($i2);

$g = inc(...);
$j = 0;
$g($j);
$g($j);
var_dump($j);

$c = Closure::fromCallable('inc');
$k = 10;
$c($k);
var_dump($k);

$sort = sort(...);
$list = [3, 1, 2];
$sort($list);
var_dump($list);

$push = array_push(...);
$push($list, 4);
var_dump(count($list));

$len = strlen(...);
var_dump($len('four'));

function thrower(&$x) { throw new Exception('from ' . __FUNCTION__); }
$t = thrower(...);
try {
    $t($j);
} catch (Exception $e) {
    echo $e->getMessage(), "\n", $e->getTrace()[0]["function"], "\n";
}
