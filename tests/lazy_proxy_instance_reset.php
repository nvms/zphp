<?php
// a proxy forwards to its instance, which can itself be made lazy again

class Obj {
    public function __construct(public string $name) {}
}

$r = new ReflectionClass(Obj::class);
$obj1 = new Obj('obj1');
$r->resetAsLazyProxy($obj1, function () use (&$obj2) {
    echo "factory 1\n";
    $obj2 = new Obj('obj2');
    return $obj2;
});
$r->initializeLazyObject($obj1);
$r->resetAsLazyProxy($obj2, function () {
    echo "factory 2\n";
    return new Obj('obj3');
});
var_dump($r->isUninitializedLazyObject($obj2));
var_dump($obj1->name);
var_dump($r->isUninitializedLazyObject($obj2));
$obj1->name = 'changed';
var_dump($obj2->name);
