<?php

// yield from array
function fromArray() {
    yield from [10, 20, 30];
}

foreach (fromArray() as $v) {
    echo $v . "\n";
}

// yield from generator
function inner() {
    yield "a";
    yield "b";
    yield "c";
    return "inner_done";
}

function outer() {
    $result = yield from inner();
    echo "inner returned: " . $result . "\n";
    yield "d";
}

foreach (outer() as $v) {
    echo $v . "\n";
}

// chained yield from
function gen1() {
    yield 1;
    yield 2;
}

function gen2() {
    yield 3;
    yield 4;
}

function combined() {
    yield from gen1();
    yield from gen2();
    yield 5;
}

foreach (combined() as $v) {
    echo $v . "\n";
}

// yield from with keys
function withKeys() {
    yield from ["x" => 100, "y" => 200];
}

foreach (withKeys() as $k => $v) {
    echo $k . "=" . $v . "\n";
}

// yield from empty array
function fromEmpty() {
    yield from [];
    yield "after_empty";
}

foreach (fromEmpty() as $v) {
    echo $v . "\n";
}
