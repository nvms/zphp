<?php
// a static initialized with `new` is null to reflection until it runs
class Counter { public $n = 0; }
function counter() {
    static $c = new Counter;
    static $limit = 10;
    $c->n++;
    return $c;
}
$rf = new ReflectionFunction('counter');
var_dump($rf->getStaticVariables());
counter();
var_dump($rf->getStaticVariables());
var_dump($rf->getStaticVariables()['c'] === counter(), counter()->n);
