<?php
class A {
    public $pub = 1;
    protected $prot = 2;
    private $priv = 3;
}

// from outside: only public
$a = new A;
print_r(get_object_vars($a));

class B {
    public $pub = 'p';
    protected $prot = 'pr';
    private $priv = 'pv';

    public function vars() { return get_object_vars($this); }
    public static function fromStatic($obj) { return get_object_vars($obj); }
}

// from inside same class: all
print_r((new B)->vars());

// from inside same class, but on different instance: still all
print_r(B::fromStatic(new B));

// dynamic properties always visible
$a = new stdClass;
$a->x = 1; $a->y = 2;
print_r(get_object_vars($a));
