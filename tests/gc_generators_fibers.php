<?php
// the cycle collector sees what waiting generators and suspended fibers
// hold (php's get_gc handlers), runs a garbage generator's finally blocks
// and a garbage fiber's before freeing, and counts as php counts

class C {
    function __construct(public $name) {}
    function __destruct() {
        echo "{$this->name} destructed\n";
    }
}

function f() {
}
$gen = function ($c) use (&$gen) {
    f($gen, yield);
};
$gen = $gen(new C("argument"));
foreach ($gen as $value) {
    break;
}
$gen = null;
gc_collect_cycles();
echo "collected\n";

function self_referencing() {
    $c = new stdClass;
    $self = yield;
    try {
        yield 2;
    } finally {
        echo "generator finally\n";
    }
}
$g = self_referencing();
$g->send($g);
unset($g);
var_dump(gc_collect_cycles());

$fiber = new Fiber(function () {
    $c = new C("fiber local");
    $fiber = Fiber::getCurrent();
    try {
        Fiber::suspend();
    } finally {
        echo "fiber finally\n";
    }
});
$fiber->start();
var_dump(gc_collect_cycles());
$fiber = null;
var_dump(gc_collect_cycles());

function plain() {
    yield 2;
}
$a = new stdClass;
$b = new stdClass;
$a->b = $b;
$b->a = $a;
$a->gen = plain();
unset($a, $b);
var_dump(gc_collect_cycles());

$unfinished = new Fiber(function () {
    try {
        echo "fiber started\n";
        Fiber::suspend();
        echo "not reached\n";
    } catch (Throwable $e) {
        echo "not caught\n";
    } finally {
        echo "unfinished finally\n";
    }
});
$unfinished->start();
$unfinished = null;
echo "done\n";
