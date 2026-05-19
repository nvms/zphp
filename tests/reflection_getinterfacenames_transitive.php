<?php
// regression: ReflectionClass::getInterfaceNames() walks transitive interface
// extension (IteratorAggregate extends Traversable) AND parent-class interfaces
// in PHP's order: parent first, child last. ArrayObject reports its full
// 5-interface set in the right order
print_r((new ReflectionClass(ArrayObject::class))->getInterfaceNames());

interface A {}
interface B extends A {}
interface C {}
class P implements B {}
class Q extends P implements C {}
print_r((new ReflectionClass(Q::class))->getInterfaceNames());

// no duplicates when both parent and child list the same interface
class R implements A {}
class S extends R implements A, B {}
print_r((new ReflectionClass(S::class))->getInterfaceNames());

// serialize on a class whose interface list claims Serializable but provides
// no serialize() method (ArrayObject is one) falls through to default property
// serialization
$ao = new ArrayObject(['x' => 1, 'y' => 2]);
$s = serialize($ao);
echo strlen($s) > 0 ? "ser-ok\n" : "ser-empty\n";
$ao2 = unserialize($s);
echo $ao2['x'] . " " . $ao2['y'] . "\n";
