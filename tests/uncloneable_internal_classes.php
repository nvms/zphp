<?php
// the internal classes php gives no clone handler can't be cloned, nor can
// objects of their subclasses, and reflection says so

class MyException extends RuntimeException {}
class MyIterator extends IteratorIterator {}

$objects = [
    new Exception('e'),
    new TypeError('t'),
    new MyException('m'),
    new XMLWriter(),
    new XMLReader(),
    new Random\Engine\Secure(),
    new Random\Randomizer(),
    new IteratorIterator(new ArrayIterator([])),
    new MyIterator(new ArrayIterator([])),
    new LimitIterator(new ArrayIterator([])),
    new ArrayIterator([]),
    new ArrayObject([]),
    new SplStack(),
];
foreach ($objects as $o) {
    $class = get_class($o);
    $cloneable = (new ReflectionClass($o))->isCloneable();
    try {
        clone $o;
        echo "$class: cloned, isCloneable ", var_export($cloneable, true), "\n";
    } catch (Error $e) {
        echo "$class: ", $e->getMessage(), ", isCloneable ", var_export($cloneable, true), "\n";
    }
}
