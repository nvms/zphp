<?php
// a reference to a property, from a class whose private property shadows an
// ancestor's of the same name, binds the slot that scope sees: foreach by
// reference, `$r = &$this->prop`, and direct writes keep each other in step

class C
{
    private $e = 'C e';
    public $a = 'a';

    public function inC()
    {
        foreach ($this as $k => &$v) {
            var_dump("$k=$v");
            $v = "changed.$k";
        }
    }

    public function refC()
    {
        $r = &$this->e;
        $r = 'changed by C';
    }

    public function getC()
    {
        return $this->e;
    }
}

class D extends C {}

class E extends D
{
    private $e = 'E e';

    public function inE()
    {
        foreach ($this as $k => &$v) {
            var_dump("$k=$v");
            $v = "changed.$k";
        }
    }

    public function refE()
    {
        $r = &$this->e;
        $r = 'changed by E';
    }

    public function both()
    {
        $r = &$this->e;
        $this->e = 5;
        var_dump($r);
        $r = 6;
        var_dump($this->e, $this->getC());
    }
}

$o = new E();
$o->inE();
var_dump($o);
$o = new E();
$o->inC();
var_dump($o);
$o = new E();
$o->refE();
var_dump($o);
$o = new E();
$o->refC();
var_dump($o);
$o = new E();
$o->both();
var_dump($o);
