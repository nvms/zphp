<?php

// `$v::class` (the ::class constant on a runtime value) must work for every
// object-like value, not just plain objects. closures, generators and fibers
// are objects in PHP, so `$closure::class` is "Closure", `$gen::class` is
// "Generator", `$fiber::class` is "Fiber". Symfony VarDumper's VarCloner does
// `$v::class` on trace-arg closures while cloning an exception, so getting this
// wrong 500'd Laravel's not-found (404) page rendering under serve.

$closure = function () {
    return 42;
};
echo "closure::class = ", $closure::class, "\n";
echo "is_object(closure) = ", var_export(is_object($closure), true), "\n";

$arrow = fn ($x) => $x * 2;
echo "arrow::class = ", $arrow::class, "\n";

function makeGen()
{
    yield 1;
    yield 2;
}
$gen = makeGen();
echo "generator::class = ", $gen::class, "\n";

$fiber = new Fiber(function () {
    Fiber::suspend();
});
echo "fiber::class = ", $fiber::class, "\n";

// the switch(true) shape VarCloner uses, with a closure in the values
foreach (['a string', 123, [1, 2], $closure, new stdClass()] as $v) {
    switch (true) {
        case is_int($v):
            echo "int\n";
            break;
        case is_string($v):
            echo "string\n";
            break;
        case is_array($v):
            echo "array\n";
            break;
        case is_object($v):
            echo "object: ", $v::class, "\n";
            break;
    }
}
