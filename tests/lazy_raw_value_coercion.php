<?php
// setRawValueWithoutLazyInitialization: the slot stops being lazy before the
// value's coercion runs, the write target is chosen before it, and a failed
// write leaves the slot lazy

class C {
    public string $a;
    public string $b;
    public int $n = 0;
    public function __construct() {
        echo "ctor\n";
        $this->a = 'a';
        $this->b = 'b';
    }
}

class Reader {
    function __construct(public object $obj) {}
    function __toString(): string {
        return $this->obj->b;
    }
}

class Thrower {
    function __toString(): string {
        throw new Exception("no string");
    }
}

$rc = new ReflectionClass(C::class);
$pa = $rc->getProperty('a');
$pb = $rc->getProperty('b');
$pn = $rc->getProperty('n');

foreach (['ghost', 'proxy'] as $kind) {
    echo "# $kind\n";
    $make = fn() => $kind === 'ghost'
        ? $rc->newLazyGhost(function ($o) { $o->__construct(); })
        : $rc->newLazyProxy(function () { return new C(); });

    // the coercion initializes the object
    $obj = $make();
    $pa->setRawValueWithoutLazyInitialization($obj, new Reader($obj));
    var_dump($rc->isUninitializedLazyObject($obj));
    var_dump($obj);

    // a failed coercion leaves the slot lazy
    $obj = $make();
    try {
        $pa->setRawValueWithoutLazyInitialization($obj, new Thrower());
    } catch (Exception $e) {
        echo $e->getMessage(), "\n";
    }
    var_dump($pa->isLazy($obj));
    var_dump($rc->isUninitializedLazyObject($obj));

    // the last lazy slot written makes the object non-lazy
    $obj = $make();
    $pa->setRawValueWithoutLazyInitialization($obj, 'x');
    $pb->setRawValueWithoutLazyInitialization($obj, 'y');
    var_dump($rc->isUninitializedLazyObject($obj));
    $pn->setRawValueWithoutLazyInitialization($obj, 5);
    var_dump($rc->isUninitializedLazyObject($obj));
    var_dump($obj);

    // an initialized proxy writes its instance
    $obj = $make();
    $rc->initializeLazyObject($obj);
    $pa->setRawValueWithoutLazyInitialization($obj, 'z');
    var_dump($obj);
}
