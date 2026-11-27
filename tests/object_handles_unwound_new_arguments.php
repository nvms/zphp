<?php
// an exception thrown while a `new`'s arguments run frees the arguments
// first and the object set aside for the call after them, and the
// temporaries an exception leaves inside eval()'d code are freed too

class Test
{
    public function __construct(public $a, public $b) {}
}

function fail()
{
    throw new Exception('fail');
}

try {
    $x = new Test(new stdClass(), [] + 0);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
var_dump(new stdClass(), new ArrayObject());

try {
    $x = new Test(new Test(new stdClass(), fail()), 1);
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
var_dump(new stdClass(), new ArrayObject());

try {
    eval('$d = new Test(new stdClass, [] + 0);');
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
var_dump(new stdClass(), new ArrayObject());

function holder()
{
    static $held = new Test(new stdClass(), fail());
}
try {
    holder();
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
var_dump(new stdClass(), new ArrayObject());
