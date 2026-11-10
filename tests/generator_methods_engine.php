<?php
// Generator's methods follow php's zend_generators.c: auto-priming, the
// return value of an aborted generator, a delegate shared by two
// generators, throw() into an array delegation, a generator resuming
// itself, and the Generator->method() frames in traces

function returns_early() {
    return 42;
    yield 1;
}
var_dump(returns_early()->getReturn());

class Holder {
    function items() { yield 1; }
}
var_dump((new Holder)->items());
var_dump((function () { yield 1; })());


function aborts() {
    throw new Exception("aborted");
    yield 1;
}
$g = aborts();
try {
    $g->next();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
try {
    $g->getReturn();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}

function shared($a = 0) {
    yield 1 + $a;
    if ($a < 1) {
        var_dump(yield from shared($a + 1));
    }
    yield 3 + $a;
    return 5 + $a;
}
function outer($g) {
    var_dump(yield from $g);
}
$inner = shared();
$gens = [outer($inner), outer($inner)];
do {
    foreach ($gens as $g) {
        var_dump($g->current());
        $g->next();
    }
} while ($gens[0]->valid());
var_dump($gens[1]->valid());

function from_array() {
    try {
        yield from [1, 2, 3];
    } catch (Exception $e) {
        echo "caught ", $e->getMessage(), "\n";
    }
    yield 10;
}
$g = from_array();
var_dump($g->current());
var_dump($g->throw(new Exception("into array")));

function resumes_itself() {
    $self = yield;
    try {
        $self->next();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
$g = resumes_itself();
$g->send($g);

try {
    $g = from_array();
    $g->throw(new stdClass);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

function traced() {
    yield 1;
    throw new LogicException("in generator");
}
$g = traced();
$g->current();
try {
    $g->next();
} catch (LogicException $e) {
    echo $e->getTraceAsString(), "\n";
}

$g = traced();
foreach ($g as $v) {}
