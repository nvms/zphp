<?php
// get_mangled_object_vars: an object's own properties under (array)'s
// mangled keys, whatever the calling scope

class A {
    public $pub = 1;
    protected $prot = 2;
    private $priv = 3;
    public int $typed;
}
class B extends A {
    private $priv = 4;
}
$b = new B;
$b->dyn = 5;
$b->{'0'} = 6;
var_dump(get_mangled_object_vars($b));
var_dump(array_map('strlen', array_keys(get_mangled_object_vars($b))));
$ao = new ArrayObject([1, 2]);
$ao->x = 'y';
var_dump(get_mangled_object_vars($ao));
var_dump(get_mangled_object_vars(new stdClass));
try {
    get_mangled_object_vars('x');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
