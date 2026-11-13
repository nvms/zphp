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
