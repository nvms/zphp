<?php
// a clone keeps a property unset() handed to the magic methods: writing it
// calls __set and reading it __get, as on the original

class Lazy {
    public int $count;
    public ?string $name = 'set';

    public function __set($name, $value) { echo "__set $name\n"; }
    public function __get($name) { echo "__get $name\n"; return 7; }
    public function __isset($name) { echo "__isset $name\n"; return true; }
}

$obj = new Lazy;
unset($obj->count, $obj->name);
$copy = clone $obj;
$copy->count = 1;
var_dump($copy->count);
var_dump(isset($copy->name));
var_dump($copy->name);

// an uninitialized property (never unset) is no magic one in the copy
$fresh = clone new Lazy;
$fresh->count = 5;
var_dump($fresh->count, $fresh->name);
try {
    $other = clone new Lazy;
    var_dump($other->count);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

// assigning in the copy initializes it there only
$obj2 = new Lazy;
unset($obj2->count);
$copy2 = clone $obj2;
$copy2->count = 3;
var_dump($obj2->count);
