<?php
// a generator declared to return by reference yields references: a foreach
// by reference binds its variable to the yielded storage; anything else is
// yielded by value with php's notice. references a generator's variables
// hold survive its yields

function &elements(array &$array) {
    foreach ($array as $key => &$value) {
        yield $key => $value;
    }
}
$array = [1, 2, 3];
foreach (elements($array) as &$value) {
    $value *= -1;
}
unset($value);
var_dump($array);

function &local() {
    $value = 1;
    yield $value;
    echo "inside: $value\n";
}
foreach (local() as &$v) {
    $v = 5;
}
unset($v);

function &element(array &$array) {
    $value = &$array[0];
    yield $value;
    echo "after yield: {$array[0]}\n";
}
$a = [1, 2];
foreach (element($a) as &$v) {
    $v = 7;
}
unset($v);
var_dump($a);

class Bag implements IteratorAggregate {
    function __construct(private array $data) {}
    function data() { return $this->data; }
    function &getIterator(): Traversable {
        foreach ($this->data as $k => &$v) {
            yield $k => $v;
        }
    }
}
$bag = new Bag([1, 2]);
foreach ($bag as &$v) {
    $v *= 10;
}
unset($v);
var_dump($bag->data());

function plain() {
    return "plain";
}
function &temporaries() {
    yield 1;
    yield plain();
    yield;
}
foreach (temporaries() as $v) {
    var_dump($v);
}

function source() {
    echo "source called\n";
    return [1, 2, 3];
}
foreach (source() as &$v) {
    $v *= 2;
}
unset($v);

function by_value() {
    return 5;
}
function &returns_reference() {
    return by_value();
}
var_dump(returns_reference());
var_dump(returns_reference());

function &yields_reference_call(&$var) {
    yield nop($var);
}
function &nop(&$var) {
    return $var;
}
$var = "foo";
foreach (yields_reference_call($var) as &$ref) {
    $ref = "bar";
}
unset($ref);
var_dump($var);
