<?php
// a built-in method that fails ends the call with its error: the script
// never carries on as if the call had returned

#[Attribute]
class NoCtor {}

#[Attribute]
class WithCtor {
    public function __construct(public $a = 1, public $b = 2) {}
}

#[NoCtor(1)] class A {}
#[NoCtor(x: 1)] class B {}
#[WithCtor(c: 2)] class C {}
#[WithCtor(1, a: 2)] class D {}
#[NoCtor(1, x: 2)] class E {}
#[WithCtor(b: 5)] class F {}
#[NoCtor] class G {}

foreach (['A', 'B', 'C', 'D', 'E', 'F', 'G'] as $c) {
    try {
        $attr = (new ReflectionClass($c))->getAttributes()[0];
        $instance = $attr->newInstance();
        echo $c, ": ", get_class($instance), " ", json_encode($instance), "\n";
    } catch (Error $e) {
        echo $c, ": ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}

// a size whose allocation overflows is a fatal error
$ar = new SplFixedArray(1);
echo "size: ", $ar->getSize(), "\n";
$ar->setSize(PHP_INT_SIZE == 8 ? 0x2000000000000001 : 0x40000001);
echo "not reached\n";
