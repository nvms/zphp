<?php
$ao = new ArrayObject([3,1,2]);
echo count($ao), "\n";
$ao->append(4);
$ao->append(0);
print_r($ao->getArrayCopy());
echo count($ao), "\n";

$ao = new ArrayObject(["c"=>3,"a"=>1,"b"=>2]);
$ao->ksort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["c"=>3,"a"=>1,"b"=>2]);
$ao->asort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject([3,1,2,4]);
$ao->asort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["banana","apple","cherry"]);
$ao->natsort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["B","a","C","b"]);
$ao->natcasesort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject([3,1,2]);
$ao->uasort(fn($a,$b) => $a - $b);
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["c"=>1,"a"=>2,"b"=>3]);
$ao->uksort(fn($a,$b) => strcmp($a,$b));
print_r($ao->getArrayCopy());

$ao = new ArrayObject([1,2,3]);
$old = $ao->exchangeArray([10,20,30,40]);
print_r($old);
print_r($ao->getArrayCopy());
echo count($ao), "\n";

$ao = new ArrayObject(["a"=>1,"b"=>2]);
$ao->offsetSet("c", 3);
echo $ao->offsetExists("c") ? "y" : "n", "\n";
echo $ao->offsetGet("a"), "\n";
$ao->offsetUnset("a");
echo $ao->offsetExists("a") ? "y" : "n", "\n";
print_r($ao->getArrayCopy());

$ao = new ArrayObject([1,2,3,4,5]);
foreach ($ao as $k => $v) echo $k, "=", $v, "\n";

$ao = new ArrayObject(["a","b","c"], 0, "ArrayIterator");
$it = $ao->getIterator();
echo get_class($it), "\n";
foreach ($it as $k => $v) echo $k, "=", $v, "\n";

$ao = new ArrayObject([1,2,3,4,5]);
$it = $ao->getIterator();
$it->seek(2);
echo $it->key(), "=", $it->current(), "\n";
$it->next();
echo $it->key(), "=", $it->current(), "\n";

$it = new ArrayIterator([10,20,30,40,50]);
echo $it->count(), "\n";
echo $it->current(), "\n";
echo $it->key(), "\n";
$it->next();
echo $it->current(), "\n";
$it->seek(3);
echo $it->key(), "=", $it->current(), "\n";
$it->rewind();
echo $it->key(), "=", $it->current(), "\n";
print_r($it->getArrayCopy());

$it = new ArrayIterator(["x"=>1,"y"=>2,"z"=>3]);
foreach ($it as $k => $v) echo $k, "=>", $v, "\n";
echo $it->count(), "\n";
print_r($it->getArrayCopy());

$it = new ArrayIterator([]);
echo $it->valid() ? "y" : "n", "\n";
echo $it->count(), "\n";

$it = new ArrayIterator(["c"=>3,"a"=>1,"b"=>2]);
$it->ksort();
print_r($it->getArrayCopy());
$it->asort();
print_r($it->getArrayCopy());

$it = new ArrayIterator([1,2,3]);
$it->append(4);
$it->append(5);
print_r($it->getArrayCopy());

$ao = new ArrayObject([1,2,3]);
$ao[] = 99;
echo $ao[3], "\n";
$ao[10] = 100;
echo $ao[10], "\n";
echo isset($ao[10]) ? "y" : "n", "\n";
echo count($ao), "\n";

$ao = new ArrayObject([5,3,8,1,9]);
$ao->asort();
$arr = [];
foreach ($ao as $k => $v) $arr[] = "$k=$v";
print_r($arr);
