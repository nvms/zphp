<?php
// a trace names "[internal function]" as the caller of a method an internal
// function called, and shows a generator argument as an object

function lines()
{
    yield 'one';
    throw new RuntimeException('read failed');
}

try {
    iterator_count(lines());
} catch (RuntimeException $e) {
    echo $e->getTraceAsString(), "\n";
}

$it = new ArrayIterator([1, 2, 3]);
try {
    array_map([$it, 'seek'], [1, 7]);
} catch (OutOfBoundsException $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n", $e->getTraceAsString(), "\n";
}
try {
    call_user_func([$it, 'seek'], 9);
} catch (OutOfBoundsException $e) {
    echo $e->getTraceAsString(), "\n";
}
try {
    $it->seek(10);
} catch (OutOfBoundsException $e) {
    echo $e->getTraceAsString(), "\n";
}
