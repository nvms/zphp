<?php
// a promoted by-reference constructor parameter makes the property a
// reference to the caller's variable

class Ary {
    public function __construct(public array &$array, public int $plain = 0) {}
}

$array = [];
$plain = 1;
$ary = new Ary($array, $plain);
$array[] = 42;
$plain = 2;
var_dump($ary->array, $ary->plain);
$ary->array[] = 'from the object';
var_dump($array);
var_dump($ary);

class Typed {
    public function __construct(public int &$count) {}
}
$n = 1;
$t = new Typed($n);
$n++;
var_dump($t->count);
try {
    $n = 'not a number';
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump($n);
