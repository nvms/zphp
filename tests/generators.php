<?php

// basic generator with foreach
function numbers() {
    yield 1;
    yield 2;
    yield 3;
}

foreach (numbers() as $n) {
    echo $n . "\n";
}

// generator with keys
function indexed() {
    yield "a" => 10;
    yield "b" => 20;
    yield "c" => 30;
}

foreach (indexed() as $k => $v) {
    echo $k . "=" . $v . "\n";
}

// generator with return value
function withReturn() {
    yield 1;
    yield 2;
    return "done";
}

$g = withReturn();
$g->next();
echo $g->current() . "\n";
$g->next();
echo $g->current() . "\n";
$g->next();
echo $g->valid() ? "valid" : "done";
echo "\n";
echo $g->getReturn() . "\n";

// infinite generator (consumed partially)
function naturals() {
    $i = 1;
    while (true) {
        yield $i;
        $i++;
    }
}

$count = 0;
foreach (naturals() as $n) {
    echo $n . "\n";
    $count++;
    if ($count >= 5) break;
}

// generator with implicit keys
function letters() {
    yield "x";
    yield "y";
    yield "z";
}

foreach (letters() as $k => $v) {
    echo $k . ":" . $v . "\n";
}

// send values to generator
function accumulator() {
    $sum = 0;
    while (true) {
        $val = yield $sum;
        if ($val === null) return;
        $sum += $val;
    }
}

$acc = accumulator();
$acc->current(); // start generator (run to first yield)
$acc->send(10);
$acc->send(20);
$acc->send(30);
echo $acc->current() . "\n";
