<?php
// appending to a property only __get provides changes a copy: php notices
class Test {
    protected $property = array('foo' => 'bar');
    function __get($name) { echo "get $name\n"; return $this->property; }
}
$obj = new Test;
$obj->property[] = 1;
$obj->property[] = 2;
$obj->missing[] = 3;
var_dump($obj);

class Holder {
    function __get($name) { return new ArrayObject(); }
}
$h = new Holder;
$h->list[] = 'kept in the returned object';
echo "done\n";

class ByRef {
    private $data = [];
    function &__get($n) { return $this->data; }
}
$r = new ByRef;
$r->x[] = 1;
$r->x[] = 2;
var_dump($r);
