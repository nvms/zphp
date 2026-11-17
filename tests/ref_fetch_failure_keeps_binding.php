<?php
// a reference fetch that fails leaves the variable bound as it was

class C {
    public $a;
    public int $b = 1;
    public int $c;
    public readonly int $r;
    public function __construct() { $this->r = 5; }
}

$obj = new C;
$ref = &$obj->b;
try {
    $ref = &$obj->c;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump($ref);
$ref = 7;
var_dump($obj);

$name = 'c';
$ref2 = &$obj->a;
try {
    $ref2 = &$obj->$name;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$ref2 = 'through';
var_dump($obj->a);

$ref3 = &$obj->a;
try {
    $ref3 = &$obj->r;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$ref3 = 'again';
var_dump($obj->a);

$n = null;
$ref4 = &$obj->b;
try {
    $ref4 = &$n->x;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump($ref4);
