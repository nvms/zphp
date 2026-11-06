<?php
// php 8.5 deprecates an object as the storage of an ArrayObject or
// ArrayIterator, from the constructor or exchangeArray()
error_reporting(E_ALL);
set_error_handler(function ($level, $message) {
    echo $level === E_DEPRECATED ? "deprecated: " : "$level: ", $message, "\n";
    return true;
});

$o = new stdClass;
new ArrayObject($o);
new ArrayIterator($o);
new RecursiveArrayIterator($o);
new ArrayObject(new ArrayObject([1]));
class MyArrayObject extends ArrayObject {}
new MyArrayObject($o);
$ao = new ArrayObject([1, 2]);
var_dump($ao->exchangeArray($o));
new ArrayObject([1]);
echo "done\n";
