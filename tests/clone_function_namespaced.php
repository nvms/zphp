<?php
namespace Foo;
var_dump(clone(object: new \stdClass));
$g = clone(...);
var_dump($g(new \stdClass));
$o = new \stdClass;
$o->x = new \stdClass;
$o->x->y = 1;
var_dump(clone($o)->x);
$y = clone($o->x);
var_dump($y);
