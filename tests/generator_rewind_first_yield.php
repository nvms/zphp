<?php
// a generator may be rewound while it stands at its first yield, however
// often it was asked for that value; once it moved on, rewind() throws

function numbers()
{
    echo "start\n";
    yield 1;
    yield 2;
}

$gen = numbers();
var_dump($gen->current());
var_dump($gen->valid());
$gen->rewind();
$gen->rewind();
var_dump($gen->key());
foreach ($gen as $n) {
    echo "got $n\n";
}
try {
    $gen->rewind();
} catch (Exception $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

$gen = numbers();
$gen->next();
try {
    $gen->rewind();
} catch (Exception $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

function nothing()
{
    return;
    yield;
}
$empty = nothing();
$empty->rewind();
var_dump($empty->valid());
$empty->rewind();
echo "rewound a finished generator that never yielded\n";

$gen = numbers();
foreach ($gen as $n) {
    echo "first pass $n\n";
    break;
}
foreach ($gen as $n) {
    echo "second pass $n\n";
}
