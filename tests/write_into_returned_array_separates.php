<?php
// writing into an array a call returned by value changes a copy, never the
// array its owners still hold

class A {
    public $b;
    public $c = [1];
    public function get() { return $this->c; }
}

$arr = [];
$a = new A;
$a->b =& $arr;
(new ReflectionProperty('A', 'b'))->getValue($a)[] = 42;
(new ReflectionProperty('A', 'b'))->getValue($a)['k'] = 43;
var_dump($a, $arr);

$a->get()[] = 2;
$a->get()['x'] = 3;
var_dump($a->c);

$g = ['g'];
function g() { global $g; return $g; }
g()[] = 'appended';
g()[5] = 'set';
var_dump($g);

$o = new ArrayObject([1, 2]);
$o->getArrayCopy()[] = 3;
var_dump(count($o));

$h = ['h' => [1]];
current($h)[] = 2;
var_dump($h);
