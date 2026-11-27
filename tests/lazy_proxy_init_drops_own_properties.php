<?php
// an initialized proxy's own properties are gone: a reference to one of
// them is no longer bound to it nor typed by it, and the values it held are
// released as the proxy initializes

class D {
    public function __construct(public string $name) {}
    public function __destruct() {
        echo "destroyed {$this->name}\n";
    }
}

class C {
    public ?C $a;
    public ?D $d;
    public $c;
}

$rc = new ReflectionClass(C::class);
$obj = $rc->newLazyProxy(function () {
    echo "factory\n";
    return new C();
});
$rc->getProperty('a')->setRawValueWithoutLazyInitialization($obj, null);
$refA = &$obj->a;
$rc->getProperty('d')->setRawValueWithoutLazyInitialization($obj, new D('pre'));

echo "init\n";
var_dump($obj->c);
echo "after\n";

$refA = 1;
var_dump($refA);
try {
    var_dump($obj->a);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump($obj);
