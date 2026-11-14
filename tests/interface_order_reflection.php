<?php
// reflection lists a class's interfaces in php's own table order, the same
// order class_implements() gives

interface I1 {}
interface I2 {}
interface I3 {}
interface I4 extends I3 {}
interface I5 extends I4 {}
interface I6 extends I5, I1, I2 {}
interface I7 extends I6 {}
class C implements I6, I1 {}
class D extends C implements Countable {
    public function count(): int { return 0; }
}

foreach (['I7', 'C', 'D', 'ReflectionClass', 'Exception', 'ArrayIterator', 'CachingIterator', 'RecursiveCachingIterator'] as $name) {
    $rc = new ReflectionClass($name);
    echo $name, ": ", implode(', ', $rc->getInterfaceNames()), "\n";
    echo "  ", implode(', ', array_keys($rc->getInterfaces())), "\n";
    echo "  ", implode(', ', class_implements($name)), "\n";
}
