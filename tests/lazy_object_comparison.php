<?php
// comparing lazy objects initializes them, the right one first, and a proxy
// compares as its instance

class C {
    public int $a;
    public $b;
    public function __construct(int $a = 1) {
        echo "construct $a\n";
        $this->a = $a;
    }
}

$reflector = new ReflectionClass(C::class);
$ghost = fn(int $a) => $reflector->newLazyGhost(function ($obj) use ($a) { $obj->__construct($a); });
$proxy = fn(int $a) => $reflector->newLazyProxy(function () use ($a) { return new C($a); });

var_dump($ghost(1) == $proxy(1));
var_dump($proxy(2) > $ghost(1));
var_dump($ghost(3) < $proxy(4));
var_dump($ghost(5) <=> $ghost(5));

$failing = $reflector->newLazyProxy(function () { throw new Exception('initializer failed'); });
try {
    var_dump($failing == new C(9));
} catch (Exception $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump($reflector->isUninitializedLazyObject($failing));

class Other { public int $a = 1; }
$lazy = $reflector->newLazyGhost(function ($obj) { echo "not initialized\n"; });
var_dump($lazy == new Other());
var_dump($reflector->isUninitializedLazyObject($lazy));
