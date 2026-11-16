<?php
// an internal method php declares non-static can't be called statically,
// except on a $this of its class

class test {
    public function method() {
        return ArrayIterator::current();
    }
}

try {
    ReflectionClass::getName();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

try {
    (new test)->method();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

class MyIterator extends ArrayIterator {
    public function current(): mixed {
        return 'wrapped ' . ArrayIterator::current();
    }
}
$it = new MyIterator([1, 2]);
echo $it->current(), "\n";

class MyException extends Exception {
    public function __construct() {
        Exception::__construct('from parent');
    }
}
echo (new MyException)->getMessage(), "\n";

// static internal methods still work
var_dump(DateTime::createFromFormat('Y-m-d', '2024-01-02') instanceof DateTime);
var_dump(Closure::fromCallable('strlen')('abc'));

// aliases and methods without parameters php declares non-static too
$calls = [
    fn() => ReflectionClass::isIterateable(),
    fn() => ReflectionClass::isIterable(),
    fn() => ReflectionClass::getExtensionName(),
    fn() => ReflectionMethod::hasPrototype(),
    fn() => ReflectionParameter::isCallable(),
    fn() => SplObjectStorage::seek(0),
    fn() => SplPriorityQueue::getExtractFlags(),
    fn() => SplFixedArray::getIterator(),
];
foreach ($calls as $call) {
    try {
        $call();
        echo "no error\n";
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
