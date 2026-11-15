<?php
// resetAsLazy*() resets only the properties the reflected class declares,
// keeps an initialized readonly property of a final class, detaches a
// reference a reset property shared, and turns an initialized proxy back
// into a plain object (its instance released) before making it lazy again

class A { public $a; }
class B extends A { public $b; }

$reflector = new ReflectionClass(A::class);
$obj = new B();
$obj->a = 1;
$obj->b = 2;
$reflector->resetAsLazyGhost($obj, function () { echo "init B\n"; });
var_dump($obj);
var_dump($obj->b);
var_dump($obj->a);
var_dump($obj);

class R {
    public readonly int $a;
    public readonly int $b;
    public function __construct(int $v, bool $setB = false) {
        try {
            $this->a = $v;
        } catch (Error $e) {
            echo get_class($e), ": ", $e->getMessage(), "\n";
        }
        if ($setB) $this->b = $v;
    }
}
final class F extends R {}

foreach ([new R(1), new F(1)] as $o) {
    $r = new ReflectionClass($o::class);
    $r->resetAsLazyGhost($o, function ($o) { $o->__construct(2, setB: true); });
    $r->initializeLazyObject($o);
    var_dump($o);
}

class T {
    public int $a;
    public function __construct() { $this->a = 1; }
}
$t = new T();
$ref = &$t->a;
(new ReflectionClass(T::class))->resetAsLazyGhost($t, function ($t) { $t->__construct(); });
$ref = 'no longer typed';
var_dump($ref, $t->a);

class P {
    public function __construct(public $v, public $proxy = null) {}
    public function __destruct() {
        echo "destruct ", $this->v, "\n";
        var_dump($this->proxy);
    }
}
$pr = new ReflectionClass(P::class);
$proxy = $pr->newLazyProxy(fn($proxy) => new P(1, $proxy));
$pr->initializeLazyObject($proxy);
$pr->resetAsLazyProxy($proxy, fn() => new P(2));
var_dump($pr->isUninitializedLazyObject($proxy));
var_dump($proxy->v);
echo "done\n";
