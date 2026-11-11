<?php
// unset on an ArrayObject with a numeric string offset removes the integer
// key, as it does on an array
$a = new ArrayObject([1, 2, 3, 4]);
unset($a["3"]);
unset($a["1"]);
var_dump(count($a), $a->getArrayCopy());

$b = new ArrayObject(["x" => 1, 5 => 2, "07" => 3]);
$b->offsetUnset("5");
$b->offsetUnset("07");
var_dump($b->getArrayCopy());

$it = new ArrayIterator([10, 20, 30]);
unset($it["0"]);
var_dump(iterator_to_array($it));
