<?php
// regression: SplObjectStorage declares the Iterator / Traversable /
// ArrayAccess interfaces so foreach uses the Iterator-method dispatch
// (rewind/valid/current/key/next) rather than falling back to property
// iteration. previously foreach on an SplObjectStorage yielded its internal
// __cursor/__objs/__info properties instead of int-counter => stored-object
$so = new SplObjectStorage();
$a = new stdClass(); $a->n = 'A';
$b = new stdClass(); $b->n = 'B';
$so->attach($a, 'info_a');
$so->attach($b, 'info_b');

// foreach key=>val: key is int counter, val is the stored object
foreach ($so as $k => $v) {
    echo gettype($k) . ":$k -> " . $v->n . " info=" . $so[$v] . "\n";
}

// foreach single-var: val is the stored object
foreach ($so as $v) {
    echo $v->n . "\n";
}

// instanceof checks
var_dump($so instanceof Iterator);
var_dump($so instanceof Traversable);
var_dump($so instanceof ArrayAccess);
var_dump($so instanceof Countable);
