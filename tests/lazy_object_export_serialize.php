<?php
// var_export initializes a lazy object before writing it, serialize leaves
// one with __serialize alone, a ghost is no longer lazy while its initializer
// runs, and isLazy() looks through an initialized proxy

class C {
    public int $a;
    public $b = 2;
    public function __construct() {
        echo "construct\n";
        $this->a = 1;
    }
}
class S {
    public int $a;
    public function __serialize(): array { return []; }
}

$reflector = new ReflectionClass(C::class);
$ghost = $reflector->newLazyGhost(function ($obj) {
    echo "initializer\n";
    var_dump($obj);
    $obj->__construct();
});
var_export($ghost);
echo "\n";

$proxy = $reflector->newLazyProxy(function () {
    echo "factory\n";
    return new C();
});
var_export($proxy);
echo "\n";

$sr = new ReflectionClass(S::class);
$lazy = $sr->newLazyGhost(function () { echo "never\n"; });
var_dump(serialize($lazy));
var_dump($sr->isUninitializedLazyObject($lazy));
$lazy = $reflector->newLazyGhost(function ($obj) { echo "init for serialize\n"; $obj->__construct(); });
var_dump(serialize($lazy));

$nested = new C();
$outer = $reflector->newLazyProxy(fn() => $nested);
$reflector->initializeLazyObject($outer);
$reflector->resetAsLazyProxy($nested, fn() => new C());
var_dump($reflector->getProperty('a')->isLazy($outer));
var_dump($reflector->getProperty('b')->isLazy($outer));
$reflector->initializeLazyObject($nested);
var_dump($reflector->getProperty('a')->isLazy($outer));
