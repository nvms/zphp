<?php
// ReflectionGenerator and ReflectionFiber keep what they reflect alive and
// refuse to look into a finished generator or a fiber that isn't running

function inner() {
    yield 1;
    yield 2;
}
function outer() {
    yield from inner();
}
class Maker {
    function make() {
        yield 1;
    }
}

$gen = outer();
$ref = new ReflectionGenerator($gen);
var_dump($ref->getExecutingLine(), $ref->isClosed());
$gen->current();
var_dump($ref->getExecutingLine(), basename($ref->getExecutingFile()));
var_dump($ref->getExecutingGenerator() === $gen, $ref->getFunction()->name);
foreach ($ref->getTrace() as $frame) {
    echo $frame['function'], ' ', $frame['line'] ?? '-', "\n";
}
foreach ($gen as $v);
var_dump($ref->isClosed(), $ref->getFunction()->name);
try {
    $ref->getExecutingLine();
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}

$m = (new Maker)->make();
$m->current();
$mref = new ReflectionGenerator($m);
var_dump(get_class($mref->getFunction()), $mref->getFunction()->class, get_class($mref->getThis()));
var_dump($mref->getExecutingLine());

try {
    new ReflectionGenerator(new stdClass);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

$fiber = new Fiber(function () {
    Fiber::suspend();
});
$fref = new ReflectionFiber($fiber);
try {
    $fref->getExecutingLine();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$fiber->start();
var_dump($fref->getExecutingLine(), basename($fref->getExecutingFile()));
var_dump($fref->getTrace()[0]['function']);
$fiber->resume();
try {
    $fref->getTrace();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    $fref->getCallable();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
